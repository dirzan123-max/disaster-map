import 'dart:convert';

import '../../core/app_http.dart';
import '../../core/world_text_ja.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 世界の地震（USGS Earthquake Hazards Program）。
///
/// 公開されていて、キーも申請も不要。2つの窓口を併せて使う。
///
/// - まとめフィード（`summary/all_day.geojson`）: 直近24時間の全地震。
///   小さい地震まで入るが 24時間より前は取れない。
/// - 検索API（FDSN `fdsnws/event/1/query`）: 期間とマグニチュードを指定できる。
///
/// 直近だけ細かく、それ以前は大きいものだけ、という形にしている。
/// 全マグニチュードで30日遡ると数万件になり、地図もアプリも耐えられないため。
/// どちらも同じ ID 体系なので、重なった分は Repository 側でまとめられる。
/// https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php
/// https://earthquake.usgs.gov/fdsnws/event/1/
class UsgsSource extends ParsingSource {
  UsgsSource({
    AppHttp? http,
    this.feed = 'all_day',
    this.history = const Duration(days: 30),
    this.historyMinimumMagnitude = 4.5,
    this.text = WorldTextJa.withoutCountries,
  }) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 英語の震源地表記を日本語にするための辞書。
  final WorldTextJa text;

  /// all_hour / all_day / significant_week など。既定は直近24時間の全地震。
  final String feed;

  /// 検索APIで遡る長さ。null なら検索APIを使わない。
  final Duration? history;

  /// 検索APIで拾うマグニチュードの下限。
  final double historyMinimumMagnitude;

  @override
  String get sourceName => 'USGS';

  Uri get endpoint => Uri.parse(
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/$feed.geojson');

  /// 指定した時刻以降・指定したマグニチュード以上を検索する。
  Uri historyEndpoint(DateTime startUtc) => Uri.parse(
        'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson'
        '&starttime=${startUtc.toIso8601String()}'
        '&minmagnitude=$historyMinimumMagnitude'
        '&orderby=time',
      );

  @override
  Future<List<DisasterEvent>> fetch() async {
    final span = history;
    final results = await Future.wait([
      _http.getText(endpoint),
      // 過去分は補助なので、落ちても直近24時間の表示は止めない。
      if (span != null)
        _http
            .getText(historyEndpoint(DateTime.now().toUtc().subtract(span)))
            .catchError((Object _) => ''),
    ]);

    // 24時間分と過去分は重なる。ID が同じものは1件にまとめる。
    final byId = <String, DisasterEvent>{};
    for (final body in results) {
      if (body.isEmpty) continue;
      for (final event in parse(body)) {
        byId.putIfAbsent(event.id, () => event);
      }
    }
    return byId.values.toList();
  }

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const [];
    final features = decoded['features'];
    if (features is! List) return const [];

    final events = <DisasterEvent>[];
    for (final feature in features) {
      if (feature is! Map<String, dynamic>) continue;
      final event = _parseFeature(feature);
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'];
    final geometry = feature['geometry'];
    if (properties is! Map<String, dynamic> ||
        geometry is! Map<String, dynamic>) {
      return null;
    }

    // GeoJSON の座標は [経度, 緯度, 深さ(km)] の順。
    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final longitude = (coordinates[0] as num?)?.toDouble();
    final latitude = (coordinates[1] as num?)?.toDouble();
    if (latitude == null || longitude == null) return null;
    final depthKm =
        coordinates.length > 2 ? (coordinates[2] as num?)?.toDouble() : null;

    final milliseconds = (properties['time'] as num?)?.toInt();
    if (milliseconds == null) return null;
    final occurredAt =
        DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

    final magnitude = (properties['mag'] as num?)?.toDouble();
    final place = (properties['place'] as String?)?.trim();
    final placeJa = place == null ? null : text.place(place);
    final title = properties['title'] as String?;
    // USGS が津波の可能性ありと判定したイベント（1 = 該当）。
    final tsunamiFlag = (properties['tsunami'] as num?)?.toInt() == 1;

    return DisasterEvent(
      id: 'usgs-${feature['id']}',
      kind: EventKind.earthquake,
      severity: Severity.fromMagnitude(magnitude),
      title: title != null
          ? text.usgsTitle(title)
          : 'M${magnitude?.toStringAsFixed(1) ?? '?'} ${placeJa ?? ''}',
      subtitle: [
        if (depthKm != null) '深さ ${depthKm.toStringAsFixed(0)}km',
        if (tsunamiFlag) '津波の可能性あり',
      ].join(' / '),
      latitude: latitude,
      longitude: longitude,
      occurredAt: occurredAt,
      magnitude: magnitude,
      depthKm: depthKm,
      areaName: placeJa,
      sourceName: sourceName,
      sourceUrl: properties['url'] as String?,
      details: [
        if (magnitude != null) 'マグニチュード: M${magnitude.toStringAsFixed(1)}',
        if (depthKm != null) '深さ: ${depthKm.toStringAsFixed(1)}km',
        if (properties['felt'] != null) '揺れを感じた報告: ${properties['felt']}件',
        if (tsunamiFlag) 'USGS が津波の可能性ありと判定',
        // 固有名詞は訳さずに残しているため、原文も併せて出す。
        if (place != null) '原文: $place',
      ],
    );
  }
}
