import 'dart:convert';

import '../../core/app_http.dart';
import '../../core/iso6709.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 日本の地震情報（気象庁 bosai）。P2P地震情報が落ちているときの代替。
///
/// 気象庁が一次情報源であるため内容は最も確実だが、
/// 一覧が 600KB 近くあるので通常運転では使わない。
/// 座標は ISO 6709 形式の文字列で入っている（例: "+41.3+139.5-10000/"）。
class JmaQuakeSource extends ParsingSource {
  JmaQuakeSource({AppHttp? http, this.limit = 50}) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 先頭から何件を取り込むか（一覧は数千件あるため制限する）。
  final int limit;

  @override
  String get sourceName => '気象庁';

  Uri get endpoint =>
      Uri.parse('https://www.jma.go.jp/bosai/quake/data/list.json');

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    final events = <DisasterEvent>[];
    final seenEventIds = <String>{};
    for (final entry in decoded.take(limit)) {
      if (entry is! Map<String, dynamic>) continue;
      // 同じ地震の続報が複数並ぶため、最初（＝最新）の1件だけ採用する。
      final eventId = entry['eid'] as String?;
      if (eventId == null || !seenEventIds.add(eventId)) continue;
      final event = _parseEntry(entry, eventId);
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseEntry(Map<String, dynamic> entry, String eventId) {
    // 震度・震源に関する情報だけを対象にする（遠地地震の解説等は除く）。
    final point = parseIso6709(entry['cod'] as String?);
    if (point == null) return null;

    final occurredAt =
        DateTime.tryParse((entry['at'] as String?) ?? '')?.toUtc();
    if (occurredAt == null) return null;

    final magnitude = double.tryParse((entry['mag'] as String?) ?? '');
    final intensity = (entry['maxi'] as String?)?.trim();
    final areaName = (entry['anm'] as String?)?.trim();

    final severity = intensity != null && intensity.isNotEmpty
        ? Severity.fromJmaScale(scaleOfIntensityLabel(intensity))
        : Severity.fromMagnitude(magnitude);

    final title = [
      if (areaName != null && areaName.isNotEmpty) areaName else '震源不明',
      if (magnitude != null && magnitude > 0)
        'M${magnitude.toStringAsFixed(1)}',
      if (intensity != null && intensity.isNotEmpty) '最大震度$intensity',
    ].join(' ');

    return DisasterEvent(
      id: 'jma-eq-$eventId',
      kind: EventKind.earthquake,
      severity: severity,
      title: title,
      subtitle: point.depthKm != null
          ? '深さ ${point.depthKm!.toStringAsFixed(0)}km'
          : null,
      latitude: point.latitude,
      longitude: point.longitude,
      occurredAt: occurredAt,
      magnitude: magnitude != null && magnitude > 0 ? magnitude : null,
      depthKm: point.depthKm,
      areaName: areaName,
      sourceName: sourceName,
      sourceUrl: 'https://www.jma.go.jp/bosai/map.html#contents=earthquake_map',
      details: [
        if (point.depthKm != null)
          '深さ ${point.depthKm!.toStringAsFixed(0)}km',
        if (entry['ttl'] is String) entry['ttl'] as String,
      ],
    );
  }

  /// 一覧の震度表記（"1" "5-" "5+" "7" など）を震度階級コードへ直す。
  static int scaleOfIntensityLabel(String label) => switch (label) {
        '1' => 10,
        '2' => 20,
        '3' => 30,
        '4' => 40,
        '5-' => 45,
        '5+' => 50,
        '6-' => 55,
        '6+' => 60,
        '7' => 70,
        _ => 0,
      };
}
