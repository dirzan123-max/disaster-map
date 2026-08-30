import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/disaster_event.dart';
import '../domain/event_kind.dart';
import '../domain/severity.dart';

/// 直近の取得結果を端末に保存しておく。
///
/// 災害時は回線が不安定になりやすいため、通信できないときでも
/// 「最後に取れた情報」と「それがいつ時点のものか」を必ず出せるようにする。
class EventCache {
  const EventCache();

  /// 地図を1つにまとめたので、保存先も1つ。
  /// 以前の地域別のキー（cached_events_japan / _world）は読まずに捨てる。
  static const String _key = 'cached_events';

  Future<void> save(List<DisasterEvent> events) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'savedAt': DateTime.now().toUtc().toIso8601String(),
      'events': events.map(_toJson).toList(),
    });
    await preferences.setString(_key, payload);
  }

  Future<CachedEvents?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = preferences.getString(_key);
    if (payload == null) return null;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return null;
      final savedAt = DateTime.tryParse(decoded['savedAt'] as String? ?? '');
      final events = (decoded['events'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_fromJson)
          .nonNulls
          .toList();
      if (savedAt == null) return null;
      return CachedEvents(savedAt: savedAt, events: events);
    } on FormatException {
      // 保存形式を変えた直後などに壊れたデータが残っていても、
      // 起動を止めずに「キャッシュなし」として扱う。
      return null;
    }
  }

  static Map<String, dynamic> _toJson(DisasterEvent event) => {
        'id': event.id,
        'kind': event.kind.name,
        'severity': event.severity.level,
        'title': event.title,
        'subtitle': event.subtitle,
        'latitude': event.latitude,
        'longitude': event.longitude,
        'occurredAt': event.occurredAt.toIso8601String(),
        'magnitude': event.magnitude,
        'depthKm': event.depthKm,
        'areaName': event.areaName,
        'countryCode': event.countryCode,
        'sourceName': event.sourceName,
        'sourceUrl': event.sourceUrl,
        'isOngoing': event.isOngoing,
        'details': event.details,
      };

  static DisasterEvent? _fromJson(Map<String, dynamic> json) {
    final occurredAt = DateTime.tryParse(json['occurredAt'] as String? ?? '');
    final id = json['id'] as String?;
    if (occurredAt == null || id == null) return null;

    return DisasterEvent(
      id: id,
      kind: EventKind.values.firstWhere(
        (kind) => kind.name == json['kind'],
        orElse: () => EventKind.other,
      ),
      severity: Severity.fromLevel((json['severity'] as num?)?.toInt() ?? 0),
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      occurredAt: occurredAt,
      magnitude: (json['magnitude'] as num?)?.toDouble(),
      depthKm: (json['depthKm'] as num?)?.toDouble(),
      areaName: json['areaName'] as String?,
      countryCode: json['countryCode'] as String?,
      sourceName: json['sourceName'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String?,
      isOngoing: json['isOngoing'] as bool? ?? false,
      details: (json['details'] as List? ?? const [])
          .map((detail) => detail.toString())
          .toList(),
    );
  }
}

class CachedEvents {
  const CachedEvents({required this.savedAt, required this.events});

  final DateTime savedAt;
  final List<DisasterEvent> events;
}
