import 'dart:convert';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 世界の自然災害（NASA EONET v3）。
///
/// 火山・山火事・暴風雨・洪水などを、衛星観測と各国機関の情報から
/// 1つのフィードにまとめている。キー不要・CORS 許可済み。
/// https://eonet.gsfc.nasa.gov/docs/v3
class EonetSource extends ParsingSource {
  EonetSource({AppHttp? http, this.days = 10, this.limit = 100})
      : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 何日前まで遡るか。
  final int days;
  final int limit;

  @override
  String get sourceName => 'NASA EONET';

  Uri get endpoint => Uri.parse(
      'https://eonet.gsfc.nasa.gov/api/v3/events?days=$days&limit=$limit&status=open');

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

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
    // geometry は時系列で複数入る。最新の 1 点を現在位置とする。
    final geometries = (entry['geometry'] as List?) ?? const [];
    if (geometries.isEmpty) return null;
    final latest = geometries.last;
    if (latest is! Map<String, dynamic>) return null;

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

    final occurredAt = DateTime.tryParse((latest['date'] as String?) ?? '')
        ?.toUtc();
    if (occurredAt == null) return null;

    final categories = (entry['categories'] as List?) ?? const [];
    final categoryId = categories.isNotEmpty && categories.first is Map
        ? (categories.first as Map)['id']?.toString()
        : null;

    final magnitudeValue = (latest['magnitudeValue'] as num?)?.toDouble();
    final magnitudeUnit = latest['magnitudeUnit'] as String?;

    final sources = (entry['sources'] as List?) ?? const [];
    final sourceUrl = sources.isNotEmpty && sources.first is Map
        ? (sources.first as Map)['url']?.toString()
        : entry['link']?.toString();

    return DisasterEvent(
      id: 'eonet-${entry['id']}',
      kind: kindOfCategory(categoryId),
      severity: severityOfCategory(categoryId),
      title: (entry['title'] as String?) ?? 'Natural event',
      subtitle: [
        if (magnitudeValue != null)
          '${magnitudeValue.toStringAsFixed(0)} ${magnitudeUnit ?? ''}'.trim(),
        if (entry['description'] is String &&
            (entry['description'] as String).isNotEmpty)
          entry['description'] as String,
      ].join(' / '),
      latitude: latitude,
      longitude: longitude,
      occurredAt: occurredAt,
      areaName: entry['description'] as String?,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      details: [
        for (final category in categories)
          if (category is Map && category['title'] != null)
            'Category: ${category['title']}',
        if (magnitudeValue != null)
          'Magnitude: $magnitudeValue ${magnitudeUnit ?? ''}'.trim(),
      ],
    );
  }

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
