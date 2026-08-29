// ===========================================================================
//  jma-alert-map / Phase 2 : 気象庁 + USGS を統合して読み込む
// ---------------------------------------------------------------------------
//  events.csv (気象庁) と events_usgs.csv (USGS) を結合し、
//  同一地震の重複を除いたうえで、期間・地域の絞り込み用の列を追加します。
//
//  Power BI Desktop で
//    データを取得 → 空のクエリ → 詳細エディター
//  を開き、この内容をすべて貼り付けてください。
//
//  ★ 書き換えが必要なのは次の DataFolder の 1 行だけです。
//     events_usgs.csv がまだ無い場合は、気象庁のデータのみで動作します。
// ===========================================================================
let
    DataFolder = "C:\Users\AS2628\AI_workbench\Sandbox\jma-alert-map\data",

    // --- 共通の列定義 ------------------------------------------------------
    Columns = {
        "event_id", "report_no", "info_type", "hypocenter",
        "occurred_at_utc", "published_at_utc",
        "lat", "lon", "depth_km", "magnitude",
        "max_intensity", "intensity_rank", "area_code",
        "source", "region", "fetched_at_utc"
    },

    // 古い形式のCSV(source / region が無いもの)を読んでも動くように補う
    EnsureColumns = (t as table, defaultSource as text) as table =>
        let
            withSource =
                if List.Contains(Table.ColumnNames(t), "source") then t
                else Table.AddColumn(t, "source", each defaultSource, type text),
            withRegion =
                if List.Contains(Table.ColumnNames(withSource), "region") then withSource
                else Table.AddColumn(withSource, "region", each "", type text)
        in
            Table.SelectColumns(withRegion, Columns, MissingField.UseNull),

    LoadCsv = (fileName as text, defaultSource as text) as table =>
        let
            raw = Csv.Document(
                    File.Contents(DataFolder & "\" & fileName),
                    [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
                  ),
            headed = Table.PromoteHeaders(raw, [PromoteAllScalars = true])
        in
            EnsureColumns(headed, defaultSource),

    // --- 読み込み ----------------------------------------------------------
    Jma  = LoadCsv("events.csv", "JMA"),

    // USGS 側は未取得でも動作させる
    Usgs = try LoadCsv("events_usgs.csv", "USGS")
           otherwise Table.FromRows({}, Columns),

    // --- 型付け ------------------------------------------------------------
    Typify = (t as table) as table =>
        Table.TransformColumnTypes(t, {
            {"event_id",       type text},
            {"report_no",      Int64.Type},
            {"info_type",      type text},
            {"hypocenter",     type text},
            {"lat",            type number},
            {"lon",            type number},
            {"depth_km",       type number},
            {"magnitude",      type number},
            {"max_intensity",  type text},
            {"intensity_rank", Int64.Type},
            {"area_code",      type text},
            {"source",         type text},
            {"region",         type text}
        }),

    JmaT  = Typify(Jma),
    UsgsT = Typify(Usgs),

    // --- 重複の判定 --------------------------------------------------------
    // 同じ地震が気象庁とUSGSの双方に現れるため、USGS側を落として気象庁を残す。
    // 判定は「発生時刻が近く、震源が近い」こと。USGSの速報値は気象庁の確定値と
    // 数十km程度ずれるため、距離のしきい値には余裕を持たせている。
    TimeToleranceSec = 120,
    DistanceToleranceKm = 100,

    Epoch = #datetimezone(1970, 1, 1, 0, 0, 0, 0, 0),

    ToEpoch = (s) =>
        try Duration.TotalSeconds(DateTimeZone.FromText(s) - Epoch) otherwise null,

    Haversine = (lat1 as number, lon1 as number, lat2 as number, lon2 as number) as number =>
        let
            R = 6371,
            rad = (d) => d * Number.PI / 180,
            dLat = rad(lat2 - lat1),
            dLon = rad(lon2 - lon1),
            a = Number.Power(Number.Sin(dLat / 2), 2)
                + Number.Cos(rad(lat1)) * Number.Cos(rad(lat2))
                  * Number.Power(Number.Sin(dLon / 2), 2)
        in
            2 * R * Number.Asin(Number.Sqrt(List.Min({1, a}))),

    JmaKeys = Table.Buffer(
        Table.SelectColumns(
            Table.AddColumn(JmaT, "epoch", each ToEpoch([occurred_at_utc]), type number),
            {"epoch", "lat", "lon"}
        )),

    UsgsEpoch = Table.AddColumn(UsgsT, "epoch", each ToEpoch([occurred_at_utc]), type number),

    UsgsFlagged = Table.AddColumn(UsgsEpoch, "is_dup", (row) =>
        let
            et = row[epoch], la = row[lat], lo = row[lon]
        in
            if et = null or la = null or lo = null then false
            else
                let
                    // まず時刻で粗く絞ってから距離を計算する
                    near = Table.SelectRows(JmaKeys,
                             each [epoch] <> null
                              and Number.Abs([epoch] - et) <= TimeToleranceSec),
                    hit  = Table.SelectRows(near,
                             each Haversine([lat], [lon], la, lo) <= DistanceToleranceKm)
                in
                    Table.RowCount(hit) > 0,
        type logical),

    UsgsUnique = Table.RemoveColumns(
                    Table.SelectRows(UsgsFlagged, each [is_dup] = false),
                    {"is_dup", "epoch"}),

    // --- 結合 --------------------------------------------------------------
    Combined = Table.Combine({JmaT, UsgsUnique}),

    // --- 表示用の列 --------------------------------------------------------
    OccurredJst = Table.AddColumn(Combined, "occurred_at_jst",
        each try DateTimeZone.RemoveZone(
                    DateTimeZone.SwitchZone(
                        DateTimeZone.FromText([occurred_at_utc]), 9))
             otherwise null, type datetime),

    FetchedJst = Table.AddColumn(OccurredJst, "fetched_at_jst",
        each try DateTimeZone.RemoveZone(
                    DateTimeZone.SwitchZone(
                        DateTimeZone.FromText([fetched_at_utc]), 9))
             otherwise null, type datetime),

    // 期間スライサー用
    WithDate = Table.AddColumn(FetchedJst, "occurred_date",
        each Date.From([occurred_at_jst]), type date),

    WithDaysAgo = Table.AddColumn(WithDate, "days_ago",
        each try Duration.Days(Date.From(DateTime.LocalNow()) - [occurred_date])
             otherwise null, Int64.Type),

    // 震度スライサー用。値が無い場合(USGSなど)も凡例に出せるようにする
    WithIntensity = Table.AddColumn(WithDaysAgo, "intensity_label",
        each if [max_intensity] = null or [max_intensity] = ""
             then "震度データなし"
             else "震度 " & [max_intensity], type text),

    // マグニチュード階級スライサー用
    WithMagBand = Table.AddColumn(WithIntensity, "magnitude_band",
        each if [magnitude] = null then "不明"
             else if [magnitude] >= 7   then "M7.0以上"
             else if [magnitude] >= 6   then "M6.0-6.9"
             else if [magnitude] >= 5   then "M5.0-5.9"
             else if [magnitude] >= 4   then "M4.0-4.9"
             else "M4.0未満", type text),

    // 地域が空(古いCSV由来)の場合をここで補う
    WithRegion = Table.AddColumn(WithMagBand, "region_final",
        each if [region] <> null and [region] <> "" then [region]
             else if [lat] = null or [lon] = null then "その他"
             else if [lat] >= 20 and [lat] <= 46 and [lon] >= 122 and [lon] <= 154 then "日本"
             else if [lat] < 0 and [lon] >= 110 and [lon] <= 180 then "オセアニア"
             else if [lat] >= 0 and [lon] >= 60 and [lon] <= 180 then "アジア"
             else if [lat] >= 15 and [lon] >= -170 and [lon] <= -50 then "北米"
             else if [lon] >= -90 and [lon] <= -30 then "中南米"
             else if [lon] >= -30 and [lon] <= 60 then "欧州・中東・アフリカ"
             else "その他", type text),

    Cleaned = Table.RemoveColumns(WithRegion, {"region"}),
    Renamed = Table.RenameColumns(Cleaned, {{"region_final", "region"}}),

    Final = Table.SelectColumns(Renamed, {
        "event_id", "source", "region", "info_type", "hypocenter",
        "occurred_at_jst", "occurred_date", "days_ago", "fetched_at_jst",
        "lat", "lon", "depth_km",
        "magnitude", "magnitude_band",
        "max_intensity", "intensity_label", "intensity_rank", "area_code"
    }),

    Sorted = Table.Sort(Final, {{"occurred_at_jst", Order.Descending}})
in
    Sorted

// ---------------------------------------------------------------------------
//  スライサーに使える列
//    occurred_date   : 期間の絞り込み（相対日付スライサーが使えます）
//    region          : 地域の絞り込み（日本 / アジア / 北米 など）
//    source          : 情報源の絞り込み（JMA / USGS）
//    magnitude_band  : 規模の絞り込み
//    intensity_label : 震度の絞り込み（intensity_rank で並べ替え）
//
//  データ範囲を画面に出すメジャー（新しいメジャーとして作成）
//
//    表示範囲 =
//        "表示範囲: "
//        & FORMAT(MIN('events'[occurred_at_jst]), "yyyy/MM/dd")
//        & " 〜 "
//        & FORMAT(MAX('events'[occurred_at_jst]), "yyyy/MM/dd")
//
//    最終取得 =
//        "最終取得: " & FORMAT(MAX('events'[fetched_at_jst]), "yyyy/MM/dd HH:mm")
//
//    件数 = COUNTROWS('events')
//
//  ※ 'events' の部分は、実際のクエリ名に合わせてください。
// ---------------------------------------------------------------------------
