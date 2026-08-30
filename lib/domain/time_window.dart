/// 「いつまでさかのぼって表示するか」の指定。
///
/// 発生からの経過時間で絞り込む。上限（[maxAge]）だけを指定すれば
/// 「直近30分」、下限（[minAge]）も指定すれば「1時間前から2時間前まで」になる。
///
/// 通知にも同じ設定を使うが、通知では下限を無視する
/// （「1〜2時間前だけ通知する」は、起きた直後の情報を取り逃がすため）。
class TimeWindow {
  const TimeWindow({this.minAge = Duration.zero, this.maxAge});

  /// これより新しいものは出さない。既定は 0（今この瞬間まで含む）。
  final Duration minAge;

  /// これより古いものは出さない。null なら制限しない。
  final Duration? maxAge;

  static const TimeWindow all = TimeWindow();

  /// 絞り込みの選択肢。画面のメニューと通知設定で共有する。
  ///
  /// 「直近○○」だけを並べる。「1時間前から2時間前まで」のような範囲は
  /// 欲しい区切りが人によって違うため、固定の選択肢は置かず
  /// 「範囲を指定…」から自由に決めてもらう。
  static const List<TimeWindow> presets = [
    TimeWindow.all,
    TimeWindow(maxAge: Duration(minutes: 30)),
    TimeWindow(maxAge: Duration(hours: 1)),
    TimeWindow(maxAge: Duration(hours: 2)),
    TimeWindow(maxAge: Duration(hours: 6)),
    TimeWindow(maxAge: Duration(hours: 24)),
    TimeWindow(maxAge: Duration(days: 3)),
    TimeWindow(maxAge: Duration(days: 7)),
    TimeWindow(maxAge: Duration(days: 15)),
    TimeWindow(maxAge: Duration(days: 30)),
  ];

  /// [limit] までに収まる選択肢だけを返す。
  /// 配信されていない期間を選ばせないためのもの。
  static List<TimeWindow> presetsWithin(Duration? limit) => [
        for (final window in presets)
          if (limit == null ||
              window.maxAge == null ||
              window.maxAge! <= limit)
            window,
      ];

  /// 「3日」「24時間」のような長さの表記。
  static String spanLabel(Duration duration) => _span(duration);

  bool get isUnbounded => maxAge == null && minAge == Duration.zero;

  /// 表示に使う判定。[now] は UTC。
  bool contains(DateTime occurredAtUtc, {DateTime? now}) {
    final age = (now ?? DateTime.now().toUtc()).difference(occurredAtUtc);
    // 端末とサーバーの時計のずれで未来の時刻が来ることがある。
    // 未来のものは「たった今」として扱い、取りこぼさない。
    final elapsed = age.isNegative ? Duration.zero : age;
    if (elapsed < minAge) return false;
    final limit = maxAge;
    return limit == null || elapsed <= limit;
  }

  /// 通知に使う判定。下限は無視し、古すぎる情報だけを落とす。
  bool containsForNotification(DateTime occurredAtUtc, {DateTime? now}) {
    final limit = maxAge;
    if (limit == null) return true;
    final age = (now ?? DateTime.now().toUtc()).difference(occurredAtUtc);
    return age.isNegative || age <= limit;
  }

  String get label {
    final limit = maxAge;
    if (limit == null) {
      return minAge == Duration.zero ? '制限なし' : '${_span(minAge)}前より古い';
    }
    if (minAge == Duration.zero) return '直近${_span(limit)}';
    return '${_span(minAge)}〜${_span(limit)}前';
  }

  static String _span(Duration duration) {
    if (duration.inMinutes < 60) return '${duration.inMinutes}分';
    // 24時間ちょうどは「1日」ではなく「24時間」と書く（選択肢の並びに合わせる）。
    if (duration.inHours <= 24) return '${duration.inHours}時間';
    return '${duration.inDays}日';
  }

  Map<String, dynamic> toJson() => {
        'minAgeMinutes': minAge.inMinutes,
        'maxAgeMinutes': maxAge?.inMinutes,
      };

  static TimeWindow fromJson(Map<String, dynamic> json) {
    final maxMinutes = (json['maxAgeMinutes'] as num?)?.toInt();
    return TimeWindow(
      minAge: Duration(minutes: (json['minAgeMinutes'] as num?)?.toInt() ?? 0),
      maxAge: maxMinutes == null ? null : Duration(minutes: maxMinutes),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimeWindow && other.minAge == minAge && other.maxAge == maxAge);

  @override
  int get hashCode => Object.hash(minAge, maxAge);

  @override
  String toString() => 'TimeWindow($label)';
}
