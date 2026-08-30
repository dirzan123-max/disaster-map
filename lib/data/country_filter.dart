import '../domain/disaster_event.dart';
import '../domain/event_kind.dart';
import 'coverage.dart';

/// どの国・地域の情報を出すかの指定。
///
/// 全種別まとめて指定する使い方（「日本とフィリピンだけ見たい」）と、
/// 種別ごとに変える使い方（「地震は日本、台風はフィリピン」）の両方がある。
/// しょっちゅう変えるものではないので、絞り込みバーではなく設定画面に置く。
class CountryFilter {
  const CountryFilter({
    this.perKind = false,
    this.all = const {},
    this.byKind = const {},
    this.includeUnknown = true,
  });

  static const CountryFilter none = CountryFilter();

  /// 種別ごとに分けて指定するか。false なら [all] を全種別に使う。
  final bool perKind;

  /// まとめて指定するときの対象（ISO 3166-1 alpha-2）。空なら絞らない。
  final Set<String> all;

  /// 種別ごとに指定するときの対象。
  final Map<EventKind, Set<String>> byKind;

  /// 外洋の地震など、どの国にも寄せられない情報を含めるか。
  /// 既定は含める（絞り込みで見落とすより、多めに出す方を選ぶ）。
  final bool includeUnknown;

  /// その種別を国で絞る意味があるか。
  ///
  /// 山火事のように情報源が最初から一国に限られている種別は、
  /// 国で絞っても「その国か、全部消えるか」にしかならないため対象外にする。
  static bool appliesTo(EventKind kind) => DataCoverage.of(kind).global;

  /// 国で絞れる種別（設定画面に並べる対象）。
  static List<EventKind> get selectableKinds => [
        for (final kind in EventKind.values)
          if (appliesTo(kind)) kind,
      ];

  /// この種別に効いている国の一覧。
  Set<String> forKind(EventKind kind) =>
      perKind ? (byKind[kind] ?? const <String>{}) : all;

  /// 1件でも国を指定しているか。
  bool get isEmpty =>
      perKind ? byKind.values.every((codes) => codes.isEmpty) : all.isEmpty;

  /// 絞り込みの対象になっている国の総数（画面の表示用）。
  int get countryCount => perKind
      ? byKind.values.expand((codes) => codes).toSet().length
      : all.length;

  bool matches(DisasterEvent event) {
    if (!appliesTo(event.kind)) return true;
    final codes = forKind(event.kind);
    if (codes.isEmpty) return true;
    final code = event.countryCode;
    if (code == null) return includeUnknown;
    return codes.contains(code);
  }

  CountryFilter copyWith({
    bool? perKind,
    Set<String>? all,
    Map<EventKind, Set<String>>? byKind,
    bool? includeUnknown,
  }) =>
      CountryFilter(
        perKind: perKind ?? this.perKind,
        all: all ?? this.all,
        byKind: byKind ?? this.byKind,
        includeUnknown: includeUnknown ?? this.includeUnknown,
      );

  /// 1つの種別の対象だけを差し替える。
  CountryFilter withKind(EventKind kind, Set<String> codes) => copyWith(
        byKind: {...byKind, kind: codes},
      );

  Map<String, dynamic> toJson() => {
        'perKind': perKind,
        'all': all.toList(),
        'byKind': {
          for (final entry in byKind.entries)
            entry.key.name: entry.value.toList(),
        },
        'includeUnknown': includeUnknown,
      };

  static CountryFilter fromJson(Map<String, dynamic> json) {
    final byKind = <EventKind, Set<String>>{};
    final stored = json['byKind'];
    if (stored is Map) {
      stored.forEach((name, codes) {
        final kind =
            EventKind.values.where((each) => each.name == name).firstOrNull;
        if (kind == null || codes is! List) return;
        byKind[kind] = codes.map((code) => code.toString()).toSet();
      });
    }
    return CountryFilter(
      perKind: json['perKind'] as bool? ?? false,
      all: (json['all'] as List? ?? const [])
          .map((code) => code.toString())
          .toSet(),
      byKind: byKind,
      includeUnknown: json['includeUnknown'] as bool? ?? true,
    );
  }
}
