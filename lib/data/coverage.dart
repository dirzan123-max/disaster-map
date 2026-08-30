import 'dart:math' as math;

import '../domain/event_kind.dart';

/// 緯度経度の矩形。データを取得できる範囲を表すのに使う。
class CoverageBox {
  const CoverageBox(this.west, this.south, this.east, this.north);

  final double west;
  final double south;
  final double east;
  final double north;

  bool overlaps(CoverageBox other) =>
      west < other.east &&
      east > other.west &&
      south < other.north &&
      north > other.south;

  /// この矩形から [cut] を切り抜いた残りを、矩形の集まりで返す。
  List<CoverageBox> subtract(CoverageBox cut) {
    if (!overlaps(cut)) return [this];

    final rest = <CoverageBox>[];
    if (cut.north < north) rest.add(CoverageBox(west, cut.north, east, north));
    if (cut.south > south) rest.add(CoverageBox(west, south, east, cut.south));

    final bottom = math.max(south, cut.south);
    final top = math.min(north, cut.north);
    if (cut.west > west) rest.add(CoverageBox(west, bottom, cut.west, top));
    if (cut.east < east) rest.add(CoverageBox(cut.east, bottom, east, top));
    return rest;
  }

  /// 経度方向に [width] 度以下へ割る。
  List<CoverageBox> splitByLongitude(double width) {
    final pieces = <CoverageBox>[];
    for (var left = west; left < east; left += width) {
      final right = math.min(left + width, east);
      if (right - left > 0.0001) {
        pieces.add(CoverageBox(left, south, right, north));
      }
    }
    return pieces;
  }
}

/// ある種別のデータを「どこまで取れているか」。
class Coverage {
  const Coverage({
    required this.global,
    required this.boxes,
    required this.areaLabel,
    this.caution,
  });

  /// 全世界を対象にできているか。
  final bool global;

  /// 全世界でないときの取得範囲。空なら取得手段そのものが無い。
  final List<CoverageBox> boxes;

  /// 「全世界」「米国のみ」のような範囲の説明。
  final String areaLabel;

  /// 範囲内でも完全ではない点の注意書き。
  final String? caution;

  bool get hasNoSource => !global && boxes.isEmpty;

  /// 地図でグレーに塗る範囲（＝取得範囲の外側）。
  ///
  /// 「世界全体の多角形に取得範囲を穴として開ける」形にはしない。
  /// flutter_map の穴あきポリゴンでは、穴の側が塗られて逆になったため、
  /// 世界全体から取得範囲を引いた矩形の集まりを自分で作って塗る。
  ///
  /// さらに、経度方向に細かく割ってから返す。
  /// 経度 -180 と 180 は地図上の同じ位置に投影されるため、
  /// 端から端まで届く矩形をそのまま渡すと、潰れたり反対側へ回り込んだりして
  /// 塗る場所が逆になる。
  List<CoverageBox> get gaps {
    if (global) return const [];
    var rest = const [world];
    for (final box in boxes) {
      rest = [for (final piece in rest) ...piece.subtract(box)];
    }
    return [for (final piece in rest) ...piece.splitByLongitude(sliceWidth)];
  }

  /// 分割する幅（度）。地図の描画のためだけの値。
  static const double sliceWidth = 30;

  /// 地図に描ける範囲の全体。Web メルカトルは南北 85 度までしか描けない。
  static const CoverageBox world = CoverageBox(-180, -85, 180, 85);
}

/// どの災害種別を、どの範囲まで取得できているかの一覧。
///
/// 実際に配信元を叩いて数えた結果に基づく（2026-08 時点）:
/// USGS の直近24時間 283 件のうち約 250 件が米国内で、国外は M4 前後以上のみ。
/// EONET の山火事は情報源が IRWIN（米国の消防データ）で、米国外は入ってこない。
/// 気象警報・津波は気象庁のみを使っているため日本国外は 0 件になる。
///
/// 地図は1つしかないので、**種別を選ぶと、その情報源が無い範囲がグレーになる**。
/// これが無いと「気象警報は日本でしか起きない」という誤解を招く。
class DataCoverage {
  const DataCoverage._();

  /// 気象庁の情報が対象とする範囲。
  /// 南鳥島（東経154度）と沖ノ鳥島（北緯20度）まで含める。
  static const CoverageBox japanBox = CoverageBox(122.0, 20.0, 154.5, 46.5);

  /// EONET の山火事（IRWIN）が対象とする米国の範囲。
  static const List<CoverageBox> unitedStatesBoxes = [
    CoverageBox(-179.5, 24.0, -66.0, 71.5), // 本土・アラスカ
    CoverageBox(-161.0, 18.0, -154.0, 23.0), // ハワイ
    CoverageBox(-68.0, 17.4, -64.4, 18.7), // プエルトリコ・米領バージン諸島
  ];

  static const Coverage _japanOnly = Coverage(
    global: false,
    boxes: [japanBox],
    areaLabel: '日本のみ',
  );

  /// 種別ごとの取得範囲。
  static Coverage of(EventKind kind) => switch (kind) {
        EventKind.earthquake => const Coverage(
            global: true,
            boxes: [],
            areaLabel: '全世界',
            caution: '日本国内は気象庁（震度つき）、国外は M4.5 以上',
          ),
        EventKind.volcano => const Coverage(
            global: true,
            boxes: [],
            areaLabel: '全世界',
            caution: '日本国内は噴火警報、国外は噴火中として登録された火山',
          ),
        EventKind.storm => const Coverage(
            global: true,
            boxes: [],
            areaLabel: '全世界',
            caution: '熱帯低気圧（台風・ハリケーン等）のみ',
          ),
        EventKind.flood || EventKind.other => const Coverage(
            global: true,
            boxes: [],
            areaLabel: '全世界',
            caution: '登録される件数が少なく、起きていても出ないことがあります',
          ),
        EventKind.wildfire => const Coverage(
            global: false,
            boxes: unitedStatesBoxes,
            areaLabel: '米国のみ',
            caution: '情報源が米国の消防データ（IRWIN）のため、米国外は入りません',
          ),
        // 津波と気象警報は気象庁だけを使っている。
        EventKind.tsunami => const Coverage(
            global: false,
            boxes: [japanBox],
            areaLabel: '日本のみ',
            caution: '気象庁の津波予報。国外の津波情報は取っていません',
          ),
        EventKind.weatherWarning => _japanOnly,
      };

  /// その種別を、どこまでさかのぼって取れるか。
  ///
  /// null は「今出ているものだけが配信される」という意味
  /// （気象警報・噴火警報など。[DisasterEvent.isOngoing] が立つので、
  /// 期間の絞り込みそのものが効かない）。
  ///
  /// 取れない期間を絞り込みの選択肢に出すと、「30日で見ているのに何も無い」
  /// という誤解を生むため、選択肢はこの値までに制限する。
  static Duration? historyOf(EventKind? kind) => switch (kind) {
        // USGS の検索API で30日ぶん（国内の気象庁ぶんは直近100件＝約1週間）。
        EventKind.earthquake => const Duration(days: 30),
        // EONET は事象が起きた（探知された）時刻を持つので、期間で絞れる。
        EventKind.volcano => const Duration(days: 365),
        EventKind.wildfire => const Duration(days: 10),
        EventKind.storm => const Duration(days: 14),
        EventKind.flood || EventKind.other => const Duration(days: 60),
        // 津波は P2P地震情報から。発表時刻を持つ。
        EventKind.tsunami => const Duration(days: 7),
        // 気象警報だけは、いつ発表されたかを取る手段が無い。
        // map.json の reportDatetime は府県予報区の最終更新時刻で、
        // 注意報が継続中でも3か月前のままだったりする。
        EventKind.weatherWarning || null => null,
      };

  /// 期間で絞れない種別に、代わりに出す言葉。
  static const String ongoingLabel = '発表中のみ';


  /// なぜ期間で絞れないのかの説明。
  static String ongoingReasonOf(EventKind kind) =>
      '${kind.labelJa}は、今発表されているものだけが配信されます。'
      '気象庁の応答に「いつ発表されたか」が入っていない'
      '（府県ごとの最終更新時刻しか無い）ため、期間では絞り込めません。';

  /// 凡例に出す一覧。実際に出てくる種別だけを並べる。
  static List<(EventKind, Coverage)> table(Iterable<EventKind> kinds) =>
      [for (final kind in kinds) (kind, of(kind))];
}
