import 'dart:convert';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 世界の地震（USGS Earthquake Hazards Program の GeoJSON フィード）。
///
/// 公開フィードで、キーも申請も不要。
/// https://earthquake.usgs.gov/earthquakes/feed/v1.0/geojson.php
class UsgsSource extends ParsingSource {
  UsgsSource({AppHttp? http, this.feed = 'all_day'}) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// all_hour / all_day / significant_week など。既定は直近24時間の全地震。
  final String feed;

  @override
  String get sourceName => 'USGS';

  Uri get endpoint => Uri.parse(
      'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/$feed.geojson');

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

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
    // USGS が津波の可能性ありと判定したイベント（1 = 該当）。
    final tsunamiFlag = (properties['tsunami'] as num?)?.toInt() == 1;

    return DisasterEvent(
      id: 'usgs-${feature['id']}',
      kind: EventKind.earthquake,
      severity: Severity.fromMagnitude(magnitude),
      title: (properties['title'] as String?) ??
          'M${magnitude?.toStringAsFixed(1) ?? '?'} ${place ?? ''}',
      subtitle: [
        if (depthKm != null) 'Depth ${depthKm.toStringAsFixed(0)} km',
        if (tsunamiFlag) 'Tsunami possible',
      ].join(' / '),
      latitude: latitude,
      longitude: longitude,
      occurredAt: occurredAt,
      magnitude: magnitude,
      depthKm: depthKm,
      areaName: place,
      sourceName: sourceName,
      sourceUrl: properties['url'] as String?,
      details: [
        if (depthKm != null) 'Depth: ${depthKm.toStringAsFixed(1)} km',
        if (properties['felt'] != null) 'Felt reports: ${properties['felt']}',
        if (tsunamiFlag) 'Tsunami flag set by USGS',
      ],
    );
  }
}
