// ===========================================================================
//  jma-alert-map / Phase 0 : 気象庁のJSONを直接読み込む
// ---------------------------------------------------------------------------
//  取得スクリプトを動かさずに、Power BI Desktop だけで動作確認したい場合に使います。
//  「更新」を押した時点の直近のイベントのみが取得され、履歴は蓄積されません。
//  履歴が必要になったら phase1_csv.pq に切り替えてください。
//
//  Power BI Desktop で
//    データを取得 → 空のクエリ → 詳細エディター
//  を開き、この内容をすべて貼り付けてください。
// ===========================================================================
let
    Source = Json.Document(
        Web.Contents("https://www.jma.go.jp/bosai/quake/data/list.json")
    ),
    AsTable = Table.FromRecords(Source),

    // 震源座標を持たない情報(震度速報・津波情報など)は地図に載せられないため除外する
    HasCoord = Table.SelectRows(AsTable,
        each Record.HasFields(_, "cod") and [cod] <> null and [cod] <> ""),

    // ISO 6709 "+32.7+130.7-10000/" は符号が区切りを兼ねている。
    // 符号の前に区切り記号を差し込んでから分割する。
    Split = Table.AddColumn(HasCoord, "coords", each
        let
            body   = Text.BeforeDelimiter([cod], "/"),
            marked = Text.Replace(Text.Replace(body, "+", "|+"), "-", "|-")
        in
            List.Select(Text.Split(marked, "|"), each _ <> "")),

    Lat = Table.AddColumn(Split, "lat", each Number.From([coords]{0}), type number),
    Lon = Table.AddColumn(Lat,   "lon", each Number.From([coords]{1}), type number),

    // 深さは負のメートル値で入る。正の km に変換する
    Depth = Table.AddColumn(Lon, "depth_km",
        each try Number.From([coords]{2}) / -1000 otherwise null, type number),

    Occurred = Table.AddColumn(Depth, "occurred_at_jst",
        each try DateTimeZone.RemoveZone(
                    DateTimeZone.SwitchZone(DateTimeZone.From([at]), 9))
             otherwise null, type datetime),

    Mag = Table.AddColumn(Occurred, "magnitude",
        each try Number.From([mag]) otherwise null, type number),

    // 最大震度は "5-" "6+" などの文字列。並べ替え用の数値キーを別に持たせる
    Rank = Table.AddColumn(Mag, "intensity_rank", each
        Record.FieldOrDefault(
            [ #"1" = 1, #"2" = 2, #"3" = 3, #"4" = 4,
              #"5-" = 5, #"5+" = 6, #"6-" = 7, #"6+" = 8, #"7" = 9 ],
            Text.From([maxi]), null), Int64.Type),

    Label = Table.AddColumn(Rank, "intensity_label",
        each if [maxi] = null or [maxi] = "" then "震度なし" else "震度 " & Text.From([maxi]),
        type text),

    Selected = Table.SelectColumns(Label, {
        "eid", "ttl", "anm", "occurred_at_jst",
        "lat", "lon", "depth_km", "magnitude",
        "maxi", "intensity_label", "intensity_rank", "acd"
    }),

    Renamed = Table.RenameColumns(Selected, {
        {"eid",  "event_id"},
        {"ttl",  "info_type"},
        {"anm",  "hypocenter"},
        {"maxi", "max_intensity"},
        {"acd",  "area_code"}
    }),

    Sorted = Table.Sort(Renamed, {{"occurred_at_jst", Order.Descending}})
in
    Sorted
