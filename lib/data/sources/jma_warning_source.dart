import 'dart:convert';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import '../area_points.dart';
import 'disaster_source.dart';

/// 気象警報・注意報の種別。コードは気象庁防災情報XMLの警報コードに対応する。
class WarningKind {
  const WarningKind(this.name, this.severity);

  final String name;
  final Severity severity;
}

/// 気象庁の警報コード表。
///
/// 発表される情報の種類は滅多に増えないため、アプリに直接持たせている。
/// 未知のコードが来た場合は「その他の警報・注意報」として扱い、
/// 情報を落とさずに表示する（[JmaWarningSource.kindOf] を参照）。
const Map<String, WarningKind> jmaWarningCodes = {
  // 特別警報
  '32': WarningKind('暴風雪特別警報', Severity.extreme),
  '33': WarningKind('大雨特別警報', Severity.extreme),
  '35': WarningKind('暴風特別警報', Severity.extreme),
  '36': WarningKind('大雪特別警報', Severity.extreme),
  '37': WarningKind('波浪特別警報', Severity.extreme),
  '38': WarningKind('高潮特別警報', Severity.extreme),
  // 警報
  '02': WarningKind('暴風雪警報', Severity.severe),
  '03': WarningKind('大雨警報', Severity.severe),
  '04': WarningKind('洪水警報', Severity.severe),
  '05': WarningKind('暴風警報', Severity.severe),
  '06': WarningKind('大雪警報', Severity.severe),
  '07': WarningKind('波浪警報', Severity.severe),
  '08': WarningKind('高潮警報', Severity.severe),
  // 注意報
  '10': WarningKind('大雨注意報', Severity.moderate),
  '12': WarningKind('大雪注意報', Severity.moderate),
  '13': WarningKind('風雪注意報', Severity.moderate),
  '14': WarningKind('雷注意報', Severity.moderate),
  '15': WarningKind('強風注意報', Severity.moderate),
  '16': WarningKind('波浪注意報', Severity.moderate),
  '17': WarningKind('融雪注意報', Severity.moderate),
  '18': WarningKind('洪水注意報', Severity.moderate),
  '19': WarningKind('高潮注意報', Severity.moderate),
  '20': WarningKind('濃霧注意報', Severity.moderate),
  '21': WarningKind('乾燥注意報', Severity.moderate),
  '22': WarningKind('なだれ注意報', Severity.moderate),
  '23': WarningKind('低温注意報', Severity.moderate),
  '24': WarningKind('霜注意報', Severity.moderate),
  '25': WarningKind('着氷注意報', Severity.moderate),
  '26': WarningKind('着雪注意報', Severity.moderate),
  '27': WarningKind('その他の注意報', Severity.moderate),
};

/// 日本の気象警報・注意報（気象庁 bosai）。
///
/// 全国分が 1 ファイルにまとまった map.json を使う。
/// 都道府県別ファイルを 47 個叩く必要がなく、気象庁への負荷も小さい。
/// 発表区域には座標が無いため、同梱の代表点表（class10）で地図に載せる。
class JmaWarningSource extends ParsingSource {
  JmaWarningSource({required this.areaPoints, AppHttp? http})
      : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 一次細分区域コード -> 代表点。tool/build_assets.py が生成したもの。
  final AreaPoints areaPoints;

  @override
  String get sourceName => '気象庁';

  Uri get endpoint =>
      Uri.parse('https://www.jma.go.jp/bosai/warning/data/warning/map.json');

  static WarningKind kindOf(String code) =>
      jmaWarningCodes[code] ??
      WarningKind('警報・注意報（コード$code）', Severity.moderate);

  @override
  Future<List<DisasterEvent>> fetch() async =>
      parse(await _http.getText(endpoint));

  @override
  List<DisasterEvent> parse(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];

    final events = <DisasterEvent>[];
    for (final office in decoded) {
      if (office is! Map<String, dynamic>) continue;
      final reportedAt = DateTime.tryParse(
              (office['reportDatetime'] as String?) ?? '')
          ?.toUtc();
      if (reportedAt == null) continue;

      final areaTypes = (office['areaTypes'] as List?) ?? const [];
      if (areaTypes.isEmpty) continue;
      // areaTypes[0] が一次細分区域（地図に出す粒度）、[1] 以降は市町村単位。
      final areas = (areaTypes.first as Map<String, dynamic>)['areas'] as List?;
      if (areas == null) continue;

      for (final area in areas) {
        if (area is! Map<String, dynamic>) continue;
        final event = _parseArea(area, reportedAt);
        if (event != null) events.add(event);
      }
    }
    return events;
  }

  DisasterEvent? _parseArea(Map<String, dynamic> area, DateTime reportedAt) {
    final code = area['code'] as String?;
    if (code == null) return null;

    final warnings = (area['warnings'] as List?) ?? const [];
    // 発表中のものだけを拾う（「解除」「発表警報・注意報はなし」は除く）。
    final active = <WarningKind>[];
    for (final warning in warnings) {
      if (warning is! Map<String, dynamic>) continue;
      final warningCode = warning['code'] as String?;
      final status = warning['status'] as String?;
      if (warningCode == null) continue;
      if (status == '解除' || status == '発表警報・注意報はなし') continue;
      active.add(kindOf(warningCode));
    }
    if (active.isEmpty) return null;

    // その区域で最も重い警報を、区域全体の深刻度とする。
    active.sort((a, b) => b.severity.level.compareTo(a.severity.level));
    final worst = active.first;

    final point = areaPoints[code];
    final areaName = point?.name ?? '区域$code';

    return DisasterEvent(
      // 発表内容が変われば ID も変わり、新しい通知として扱われる。
      id: 'jma-warn-$code-${active.map((w) => w.name).join(",")}',
      kind: EventKind.weatherWarning,
      severity: worst.severity,
      title: '$areaName ${worst.name}',
      subtitle: active.length > 1
          ? active.map((w) => w.name).join('、')
          : null,
      latitude: point?.latitude,
      longitude: point?.longitude,
      occurredAt: reportedAt,
      areaName: areaName,
      sourceName: sourceName,
      sourceUrl: 'https://www.jma.go.jp/bosai/warning/#area_type=offices',
      details: active.map((w) => w.name).toList(),
    );
  }
}
