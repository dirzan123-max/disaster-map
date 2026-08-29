import 'dart:convert';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import '../area_points.dart';
import 'disaster_source.dart';

/// 日本の噴火警報・予報（気象庁 bosai）。
///
/// 発表中の火山警報だけが入った小さな JSON。火山コード（eventId）を
/// 同梱の火山座標表と突き合わせて地図に載せる。
class JmaVolcanoSource extends ParsingSource {
  JmaVolcanoSource({required this.volcanoPoints, AppHttp? http})
      : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 火山コード -> 座標。tool/build_assets.py が生成したもの。
  final AreaPoints volcanoPoints;

  @override
  String get sourceName => '気象庁';

  Uri get endpoint =>
      Uri.parse('https://www.jma.go.jp/bosai/volcano/data/warning.json');

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    final events = <DisasterEvent>[];
    for (final entry in decoded) {
      if (entry is! Map<String, dynamic>) continue;
      final event = _parseVolcano(entry);
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseVolcano(Map<String, dynamic> entry) {
    final volcanoCode = entry['eventId'] as String?;
    if (volcanoCode == null) return null;
    final reportedAt =
        DateTime.tryParse((entry['reportDatetime'] as String?) ?? '')?.toUtc();
    if (reportedAt == null) return null;

    // volcanoInfos[].items[].name に「入山危険」「噴火警報」などの語が入る。
    final statuses = <String>[];
    for (final info in (entry['volcanoInfos'] as List?) ?? const []) {
      if (info is! Map<String, dynamic>) continue;
      for (final item in (info['items'] as List?) ?? const []) {
        if (item is! Map<String, dynamic>) continue;
        final name = (item['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty && !statuses.contains(name)) {
          statuses.add(name);
        }
      }
    }
    if (statuses.isEmpty) return null;

    final point = volcanoPoints[volcanoCode];
    final volcanoName = point?.name ?? '火山$volcanoCode';
    final severity = statuses
        .map(severityOfStatus)
        .reduce((a, b) => a.level >= b.level ? a : b);

    return DisasterEvent(
      id: 'jma-vol-$volcanoCode-${reportedAt.millisecondsSinceEpoch}',
      kind: EventKind.volcano,
      severity: severity,
      title: '$volcanoName ${statuses.first}',
      subtitle: statuses.length > 1 ? statuses.skip(1).join('、') : null,
      latitude: point?.latitude,
      longitude: point?.longitude,
      occurredAt: reportedAt,
      areaName: volcanoName,
      sourceName: sourceName,
      sourceUrl: 'https://www.jma.go.jp/bosai/map.html#contents=volcano',
      details: statuses,
    );
  }

  /// 噴火警戒レベルの表現から深刻度を決める。
  ///
  /// 気象庁は数値レベルではなく「居住地域厳重警戒」「入山危険」などの
  /// キーワードで発表するため、語で判定している。
  static Severity severityOfStatus(String status) {
    if (status.contains('避難') || status.contains('居住地域')) {
      return Severity.extreme; // レベル4〜5 相当
    }
    if (status.contains('入山') || status.contains('山頂')) {
      return Severity.severe; // レベル3 相当
    }
    if (status.contains('火口周辺')) {
      return Severity.moderate; // レベル2 相当
    }
    if (status.contains('活火山であることに留意')) {
      return Severity.minor; // レベル1 相当
    }
    return Severity.info;
  }
}
