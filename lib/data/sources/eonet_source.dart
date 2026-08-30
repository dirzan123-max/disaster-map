import 'dart:convert';

import '../../core/app_http.dart';
import '../../core/time_format.dart';
import '../../core/world_text_ja.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 世界の自然災害（NASA EONET v3）。
///
/// 火山・山火事・暴風雨・洪水などを、衛星観測と各国機関の情報から
/// 1つのフィードにまとめている。キー不要・CORS 許可済み。
/// https://eonet.gsfc.nasa.gov/docs/v3
/// 取得するカテゴリと、その遡り日数・件数。
///
/// EONET の日付は「最後に観測された日」で、現象ごとに続く長さが違う。
/// 全カテゴリをまとめて1回で取ると、件数の多い山火事だけで上限が埋まり、
/// 噴火中の火山が 1 件も出てこなくなる（実際に days=120・limit=300 で
/// 300 件中 293 件が山火事になった）。そのためカテゴリごとに分けて取る。
class EonetCategory {
  const EonetCategory(this.id, {required this.days, required this.limit});

  final String id;
  final int days;
  final int limit;
}

/// 世界の自然災害（NASA EONET v3）。
///
/// 火山・山火事・暴風雨・洪水などを、衛星観測と各国機関の情報から
/// 1つのフィードにまとめている。キー不要・CORS 許可済み。
/// https://eonet.gsfc.nasa.gov/docs/v3
class EonetSource extends ParsingSource {
  EonetSource({
    AppHttp? http,
    this.categories = defaultCategories,
    this.text = WorldTextJa.withoutCountries,
  }) : _http = http ?? AppHttp();

  final AppHttp _http;

  static const List<EonetCategory> defaultCategories = [
    // 山火事は米国の消防データが元で件数が多い。直近だけ取る。
    EonetCategory('wildfires', days: 10, limit: 100),
    // 噴火は数か月「継続中」のまま更新されないことがあるため長く取る。
    EonetCategory('volcanoes', days: 365, limit: 100),
    EonetCategory('severeStorms', days: 14, limit: 100),
    EonetCategory('floods', days: 60, limit: 50),
    EonetCategory('landslides', days: 60, limit: 50),
  ];

  final List<EonetCategory> categories;

  /// 英語の見出し・カテゴリを日本語にするための辞書。
  final WorldTextJa text;

  @override
  String get sourceName => 'NASA EONET';

  Uri endpointFor(EonetCategory category) =>
      Uri.parse('https://eonet.gsfc.nasa.gov/api/v3/events'
          '?category=${category.id}&days=${category.days}'
          '&limit=${category.limit}&status=open');

  /// カテゴリごとに並列で取得する。
  /// 一部のカテゴリが落ちても、取れた分は返す（全滅したときだけ例外にする）。
  @override
  Future<List<DisasterEvent>> fetch() async {
    final results = await Future.wait(
      categories.map((category) async {
        try {
          return parse(await _http.getText(endpointFor(category)));
        } catch (error) {
          return null;
        }
      }),
    );

    if (results.every((events) => events == null)) {
      // 全部落ちたときだけ失敗にする。画面には「取得失敗」として出る。
      throw Exception('EONET のどのカテゴリも取得できませんでした');
    }

    final byId = <String, DisasterEvent>{};
    for (final events in results.nonNulls) {
      for (final event in events) {
        byId.putIfAbsent(event.id, () => event);
      }
    }
    return byId.values.toList();
  }

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final entries = decoded['events'];
    if (entries is! List) return const [];

    final events = <DisasterEvent>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) continue;
      final event = _parseEvent(entry);
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseEvent(Map<String, dynamic> entry) {
    // geometry は時系列で複数入る（台風なら経路）。
    // 位置は最新の1点、時刻は最初の1点＝発生・探知した時刻を使う。
    // 「いつ起きたか」で絞り込めるようにするため
    // （最新の観測時刻にすると、続いている限り常に「今」になってしまう）。
    final geometries = (entry['geometry'] as List?) ?? const [];
    if (geometries.isEmpty) return null;
    final latest = geometries.last;
    final earliest = geometries.first;
    if (latest is! Map<String, dynamic> || earliest is! Map<String, dynamic>) {
      return null;
    }

    final coordinates = latest['coordinates'];
    double? latitude;
    double? longitude;
    if (latest['type'] == 'Point' &&
        coordinates is List &&
        coordinates.length >= 2) {
      longitude = (coordinates[0] as num?)?.toDouble();
      latitude = (coordinates[1] as num?)?.toDouble();
    } else if (coordinates is List && coordinates.isNotEmpty) {
      // Polygon の場合は外周の平均を代表点にする。
      final ring = coordinates.first;
      if (ring is List && ring.isNotEmpty) {
        var sumLon = 0.0;
        var sumLat = 0.0;
        var count = 0;
        for (final position in ring) {
          if (position is List && position.length >= 2) {
            sumLon += (position[0] as num).toDouble();
            sumLat += (position[1] as num).toDouble();
            count++;
          }
        }
        if (count > 0) {
          longitude = sumLon / count;
          latitude = sumLat / count;
        }
      }
    }
    if (latitude == null || longitude == null) return null;

    final occurredAt =
        DateTime.tryParse((earliest['date'] as String?) ?? '')?.toUtc();
    final observedAt =
        DateTime.tryParse((latest['date'] as String?) ?? '')?.toUtc();
    if (occurredAt == null) return null;

    final categories = (entry['categories'] as List?) ?? const [];
    final categoryId = categories.isNotEmpty && categories.first is Map
        ? (categories.first as Map)['id']?.toString()
        : null;

    final magnitudeValue = (latest['magnitudeValue'] as num?)?.toDouble();
    final magnitudeUnit = latest['magnitudeUnit'] as String?;

    final title = entry['title'] as String?;
    final description = entry['description'] as String?;
    final sources = (entry['sources'] as List?) ?? const [];
    final sourceUrl = sources.isNotEmpty && sources.first is Map
        ? (sources.first as Map)['url']?.toString()
        : entry['link']?.toString();

    return DisasterEvent(
      id: 'eonet-${entry['id']}',
      kind: kindOfCategory(categoryId),
      severity: severityOfCategory(categoryId),
      title: title == null ? '自然現象' : text.eonetTitle(title),
      subtitle: [
        if (magnitudeValue != null)
          '${magnitudeValue.toStringAsFixed(0)}${WorldTextJa.unit(magnitudeUnit)}',
        if (description != null && description.isNotEmpty) description,
      ].join(' / '),
      latitude: latitude,
      longitude: longitude,
      occurredAt: occurredAt,
      areaName: description,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      details: [
        for (final category in categories)
          if (category is Map && category['title'] != null)
            '種類: ${WorldTextJa.category('${category['title']}')}',
        if (magnitudeValue != null)
          '規模: ${_number(magnitudeValue)}${WorldTextJa.unit(magnitudeUnit)}',
      if (observedAt != null && observedAt != occurredAt)
        '最終観測: ${formatLocalFull(observedAt)}',
        // 固有名詞は訳さずに残しているため、原文も併せて出す。
        if (title != null) '原文: $title',
      ],
    );
  }

  /// 「10000.0エーカー」ではなく「10000エーカー」と出す。
  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  static EventKind kindOfCategory(String? categoryId) => switch (categoryId) {
        'wildfires' => EventKind.wildfire,
        'volcanoes' => EventKind.volcano,
        'severeStorms' => EventKind.storm,
        'floods' => EventKind.flood,
        'earthquakes' => EventKind.earthquake,
        _ => EventKind.other,
      };

  /// EONET は深刻度を持たないため、災害の種類ごとに既定値を割り当てる。
  ///
  /// 「観測されて公開された時点で注意に値する」という前提に立ち、
  /// 生命に直結しやすい火山・洪水を一段重く扱う。
  static Severity severityOfCategory(String? categoryId) =>
      switch (categoryId) {
        'volcanoes' => Severity.severe,
        'floods' => Severity.severe,
        'severeStorms' => Severity.moderate,
        'wildfires' => Severity.moderate,
        'earthquakes' => Severity.moderate,
        _ => Severity.minor,
      };
}
