// ===========================================================================
//  jma-alert-map / Phase 1 : ローカルCSVを読み込む
// ---------------------------------------------------------------------------
//  Power BI Desktop で
//    データを取得 → 空のクエリ → 詳細エディター
//  を開き、この内容をすべて貼り付けてください。
//
//  ★ 書き換えが必要なのは次の DataFolder の 1 行だけです。
//     このキットを別の PC に渡した場合は、その PC 上の data フォルダの
//     絶対パスに変更してください。それ以外は変更不要です。
// ===========================================================================
let
    // このキットの data フォルダの絶対パス
    DataFolder = "C:\Users\AS2628\AI_workbench\Sandbox\jma-alert-map\data",

    Source = Csv.Document(
        File.Contents(DataFolder & "\events.csv"),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    Promoted = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    // 取得スクリプト側で整形済みのため、ここでは型付けのみ行う
    Typed = Table.TransformColumnTypes(Promoted, {
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
        {"area_code",      type text}
    }),

    // UTCで保持している時刻を、表示用の日本時間に変換する
    OccurredJst = Table.AddColumn(Typed, "occurred_at_jst",
        each try DateTimeZone.RemoveZone(
                    DateTimeZone.SwitchZone(
                        DateTimeZone.FromText([occurred_at_utc]), 9))
             otherwise null,
        type datetime),

    PublishedJst = Table.AddColumn(OccurredJst, "published_at_jst",
        each try DateTimeZone.RemoveZone(
                    DateTimeZone.SwitchZone(
                        DateTimeZone.FromText([published_at_utc]), 9))
             otherwise null,
        type datetime),

    // 期間フィルタ用の日付列。地図の初期表示を絞るのに使う
    WithDate = Table.AddColumn(PublishedJst, "occurred_date",
        each Date.From([occurred_at_jst]), type date),

    // 震度未観測(有感でない)のイベントを凡例で扱いやすくする
    WithLabel = Table.AddColumn(WithDate, "intensity_label",
        each if [max_intensity] = null or [max_intensity] = ""
             then "震度なし"
             else "震度 " & [max_intensity],
        type text),

    Final = Table.SelectColumns(WithLabel, {
        "event_id", "report_no", "info_type", "hypocenter",
        "occurred_at_jst", "published_at_jst", "occurred_date",
        "lat", "lon", "depth_km", "magnitude",
        "max_intensity", "intensity_label", "intensity_rank", "area_code"
    }),

    Sorted = Table.Sort(Final, {{"occurred_at_jst", Order.Descending}})
in
    Sorted

// ---------------------------------------------------------------------------
//  地図への割り当て（Azure Maps ビジュアル）
//    緯度        : lat
//    経度        : lon
//    サイズ      : magnitude
//    凡例        : intensity_label
//    ツールヒント: hypocenter / occurred_at_jst / depth_km
//
//  intensity_rank は「列で並べ替え」で intensity_label の並び順を
//  震度の強さ順にするために使います。
// ---------------------------------------------------------------------------
