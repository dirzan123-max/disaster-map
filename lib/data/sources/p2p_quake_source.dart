import 'dart:convert';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import 'disaster_source.dart';

/// 日本の地震・津波予報（P2P地震情報 API v2）。
///
/// 気象庁の発表を JSON へ整形して配信している無償 API。
/// ボランティア運営のため、呼び出し間隔を空けること・素性を名乗ることを
/// AppHttp と DisasterRepository 側で守っている。
/// https://www.p2pquake.net/develop/json_api_v2/
class P2pQuakeSource extends ParsingSource {
  /// [limit] は取得する件数。API が受け付ける上限が 100 で、
  /// 有感地震のペースだとおおよそ 1 週間分にあたる。
  /// 期間フィルタで遡れる長さは、ここが上限になる。
  P2pQuakeSource({AppHttp? http, this.limit = 100}) : _http = http ?? AppHttp();

  final AppHttp _http;
  final int limit;

  @override
  String get sourceName => 'P2P地震情報 / 気象庁';

  /// codes は繰り返し指定する（カンマ区切りは 400 が返る）。
  /// 551 = 地震情報、552 = 津波予報。
  Uri get endpoint => Uri.parse(
      'https://api.p2pquake.net/v2/history?codes=551&codes=552&limit=$limit');

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

  /// WebSocket から届く1件ぶんの JSON を読む。
  ///
  /// 配信される中身はまとめて取得したときと同じ形なので、
  /// 配列に包んで同じ変換にかける。地震・津波以外のコードは無視される。
  List<DisasterEvent> parseMessage(String message) => parse('[$message]');

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    final events = <DisasterEvent>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final event = switch (entry['code']) {
        551 => _parseEarthquake(entry),
        552 => _parseTsunami(entry),
        _ => null,
      };
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseEarthquake(Map<String, dynamic> entry) {
    final earthquake = entry['earthquake'];
    if (earthquake is! Map<String, dynamic>) return null;
    final hypocenter = earthquake['hypocenter'];
    if (hypocenter is! Map<String, dynamic>) return null;

    final latitude = _toDouble(hypocenter['latitude']);
    final longitude = _toDouble(hypocenter['longitude']);
    // P2P は震源不明を -200 などで表すため、範囲外なら座標なしとして扱う。
    final hasLocation = latitude != null &&
        longitude != null &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;

    final magnitude = _toDouble(hypocenter['magnitude']);
    final maxScale = _toInt(earthquake['maxScale']) ?? -1;
    final areaName = (hypocenter['name'] as String?)?.trim();
    final occurredAt = _parseJst(earthquake['time'] as String?) ??
        _parseJst(entry['time'] as String?);
    if (occurredAt == null) return null;

    final rawDepth = _toDouble(hypocenter['depth']);
    final depthKm = rawDepth != null && rawDepth >= 0 ? rawDepth : null;
    final tsunamiNote = switch (earthquake['domesticTsunami']) {
      'Warning' => '津波警報が発表されています',
      'Watch' => '津波注意報が発表されています',
      'Checking' => '津波の影響を調査中',
      'NonEffective' => '若干の海面変動の可能性',
      _ => null,
    };

    // 震度が観測されていれば震度を、無ければマグニチュードを深刻度の根拠にする。
    final severity = maxScale >= 10
        ? Severity.fromJmaScale(maxScale)
        : Severity.fromMagnitude(magnitude);

    final title = [
      if (areaName != null && areaName.isNotEmpty) areaName else '震源不明',
      if (magnitude != null && magnitude > 0)
        'M${magnitude.toStringAsFixed(1)}',
      if (maxScale >= 10) '最大震度${_scaleLabel(maxScale)}',
    ].join(' ');

    final subtitle = [
      if (depthKm != null) '深さ ${depthKm.toStringAsFixed(0)}km',
      ?tsunamiNote,
    ].join(' / ');

    final points = (entry['points'] as List?) ?? const [];
    final details = <String>[
      if (depthKm != null) '深さ ${depthKm.toStringAsFixed(0)}km',
      ?tsunamiNote,
      for (final point in points.take(15))
        if (point is Map<String, dynamic>)
          '${point['pref'] ?? ''} ${point['addr'] ?? ''} 震度${_scaleLabel(_toInt(point['scale']) ?? 0)}',
    ];

    return DisasterEvent(
      id: 'p2p-eq-${entry['id']}',
      kind: EventKind.earthquake,
      severity: severity,
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      latitude: hasLocation ? latitude : null,
      longitude: hasLocation ? longitude : null,
      occurredAt: occurredAt,
      magnitude: magnitude != null && magnitude > 0 ? magnitude : null,
      depthKm: depthKm,
      areaName: areaName,
      sourceName: sourceName,
      sourceUrl: 'https://www.jma.go.jp/bosai/map.html#contents=earthquake_map',
      details: details,
    );
  }

  DisasterEvent? _parseTsunami(Map<String, dynamic> entry) {
    final areas = (entry['areas'] as List?) ?? const [];
    if (areas.isEmpty) return null;
    final cancelled = entry['cancelled'] == true;

    // 予報区のうち最も重いものを、この津波情報全体の深刻度とする。
    var severity = Severity.info;
    final areaNames = <String>[];
    for (final area in areas) {
      if (area is! Map<String, dynamic>) continue;
      final name = (area['name'] as String?)?.trim();
      if (name != null && name.isNotEmpty) areaNames.add(name);
      final grade = switch (area['grade']) {
        'MajorWarning' => Severity.extreme, // 大津波警報
        'Warning' => Severity.severe, // 津波警報
        'Watch' => Severity.moderate, // 津波注意報
        _ => Severity.info,
      };
      if (grade.level > severity.level) severity = grade;
    }

    final occurredAt = _parseJst(entry['time'] as String?);
    if (occurredAt == null) return null;

    return DisasterEvent(
      id: 'p2p-ts-${entry['id']}',
      kind: EventKind.tsunami,
      severity: cancelled ? Severity.info : severity,
      title: cancelled ? '津波予報 解除' : '津波予報（${severity.labelJa}）',
      subtitle: areaNames.take(3).join('、'),
      // 予報区は面で発表され代表点を持たないため、地図には出さずリストに載せる。
      occurredAt: occurredAt,
      areaName: areaNames.isEmpty ? null : areaNames.first,
      sourceName: sourceName,
      sourceUrl: 'https://www.jma.go.jp/bosai/map.html#contents=tsunami',
      details: areaNames,
    );
  }

  static String _scaleLabel(int scale) => switch (scale) {
        10 => '1',
        20 => '2',
        30 => '3',
        40 => '4',
        45 => '5弱',
        50 => '5強',
        55 => '6弱',
        60 => '6強',
        70 => '7',
        _ => '不明',
      };

  /// P2P の時刻は "2026/08/29 08:14:00" 形式の日本時間。UTC に直して返す。
  static DateTime? _parseJst(String? text) {
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'(\d{4})/(\d{2})/(\d{2}) (\d{2}):(\d{2}):(\d{2})')
        .firstMatch(text);
    if (match == null) return null;
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    ).subtract(const Duration(hours: 9));
  }

  static double? _toDouble(Object? value) => switch (value) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static int? _toInt(Object? value) => switch (value) {
        num n => n.toInt(),
        String s => int.tryParse(s),
        _ => null,
      };
}
