/// 全データソース共通の深刻度スケール。
///
/// 震度・マグニチュード・気象庁の警報種別・EONET のカテゴリといった
/// 尺度の異なる指標を、すべてこの 5 段階へ写像する。
/// 地図の色分け・凡例・通知しきい値は、すべてこの値だけを見る。
enum Severity {
  info(0),
  minor(1),
  moderate(2),
  severe(3),
  extreme(4);

  const Severity(this.level);

  /// 0（情報）〜 4（最も深刻）。比較・しきい値判定に使う。
  final int level;

  bool operator >=(Severity other) => level >= other.level;
  bool operator >(Severity other) => level > other.level;
  bool operator <=(Severity other) => level <= other.level;
  bool operator <(Severity other) => level < other.level;

  static Severity fromLevel(int level) =>
      Severity.values[level.clamp(0, Severity.values.length - 1)];

  String get labelJa => switch (this) {
        Severity.info => '情報',
        Severity.minor => '軽微',
        Severity.moderate => '注意',
        Severity.severe => '警戒',
        Severity.extreme => '重大',
      };

  /// 絞り込みで選べる下限。「情報以上」は全件表示と同じ意味になり
  /// 選択肢として働かないため、ここには入れない。
  static const List<Severity> filterOptions = [
    Severity.minor,
    Severity.moderate,
    Severity.severe,
    Severity.extreme,
  ];

  /// 通知で選べる下限。画面より一段狭くしてある。
  ///
  /// 「軽微以上」で通知すると、震度1・2 の地震や小さな噴火まで鳴り続けて
  /// 通知として役に立たなくなるため、注意以上だけにしている。
  static const List<Severity> notifyOptions = [
    Severity.moderate,
    Severity.severe,
    Severity.extreme,
  ];

  /// 通知の下限として使える値に丸める。
  Severity get forNotification =>
      level < Severity.moderate.level ? Severity.moderate : this;

  /// 絞り込みに使う深刻度。
  ///
  /// 震度やマグニチュードが分からず [info] になった情報を切り捨てないよう、
  /// 絞り込みのうえでは「軽微」と同じ扱いにする。
  Severity get forFilter => this == Severity.info ? Severity.minor : this;

  /// 気象庁の震度階級コード（10 = 震度1 … 70 = 震度7）を写像する。
  static Severity fromJmaScale(int scale) {
    if (scale >= 55) return Severity.extreme; // 震度6弱以上
    if (scale >= 45) return Severity.severe; // 震度5弱・5強
    if (scale >= 30) return Severity.moderate; // 震度3・4
    if (scale >= 10) return Severity.minor; // 震度1・2
    return Severity.info;
  }

  /// マグニチュードを写像する（世界版の地震で使用）。
  static Severity fromMagnitude(double? magnitude) {
    if (magnitude == null) return Severity.info;
    if (magnitude >= 7.0) return Severity.extreme;
    if (magnitude >= 6.0) return Severity.severe;
    if (magnitude >= 4.5) return Severity.moderate;
    return Severity.minor;
  }
}
