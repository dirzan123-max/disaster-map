import 'package:xml/xml.dart';

import '../../core/app_http.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../area_points.dart';
import 'disaster_source.dart';
import 'jma_warning_source.dart';

/// 気象警報・注意報（気象庁 防災情報XML）。
///
/// bosai の JSON（`warning/map.json`）は「今出ている警報の一覧」を1ファイルで
/// くれるので扱いやすいが、**いつ発表されたかが入っていない**。
/// 入っている `reportDatetime` は府県予報区の最終更新時刻で、
/// 実際に3か月更新されないまま止まっていたこともある。
/// これでは期間で絞り込めないため、発表ごとの XML を読む形にした。
///
/// - フィード（`extra.xml`）に発表の一覧が並ぶ。約400件、うち気象警報が120件ほど
/// - 各エントリの XML に、発表時刻・警報の種類・一次細分区域コードが入っている
/// - 区域コードは bosai と同じなので、同梱の代表点表がそのまま使える
///
/// CORS は許可されているので、Web 版からも同じように叩ける。
/// 警報コードの表は [JmaWarningSource] のものをそのまま使う。
/// https://xml.kishou.go.jp/
class JmaWarningXmlSource extends DisasterSource {
  JmaWarningXmlSource({
    required this.areaPoints,
    AppHttp? http,
    this.limit = 20,
    this.longFeed = false,
  }) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 一次細分区域コード -> 代表点。tool/build_assets.py が生成したもの。
  final AreaPoints areaPoints;

  /// 個別に開く発表の件数。
  ///
  /// 府県ぶん全部（最大58）を開くと、災害時の細い回線では重い。
  /// 新しい順に絞り、古い府県は次の更新で拾う。
  final int limit;

  /// 長期フィード（約1週間ぶん）を使うか。既定は直近ぶんの高頻度フィード。
  final bool longFeed;

  @override
  String get sourceName => '気象庁';

  /// 発表の一覧。extra が随時・extra_l がその長期版。
  Uri get feedEndpoint => Uri.parse(
        'https://www.data.jma.go.jp/developer/xml/feed/'
        '${longFeed ? 'extra_l' : 'extra'}.xml',
      );

  /// フィードに並ぶ、気象警報・注意報の発表の見出し。
  static const String warningTitle = '気象特別警報・警報・注意報';

  /// 一次細分区域（地図に出す粒度）の情報が入っている節。
  static const String areaSection = '気象警報・注意報（一次細分区域等）';

  @override
  Future<List<DisasterEvent>> fetch() async {
    final urls = parseFeed(await _http.getText(feedEndpoint));
    if (urls.isEmpty) return const [];

    final bodies = await Future.wait(
      urls.take(limit).map((url) async {
        try {
          return await _http.getText(Uri.parse(url));
        } catch (_) {
          // 1つ落ちても他の府県の警報は出す。
          return '';
        }
      }),
    );

    final events = <DisasterEvent>[];
    for (final body in bodies) {
      if (body.isEmpty) continue;
      events.addAll(parseReport(body));
    }
    return events;
  }

  /// フィードから、気象警報の発表 XML の URL を新しい順に取り出す。
  ///
  /// 同じ府県で何度も更新されるため、府県ごとに最新の1件だけを残す。
  /// ファイル名の末尾が府県予報区コードになっている
  /// （`20260830082024_0_VPWW53_250000.xml` の `250000`）。
  List<String> parseFeed(String body) {
    final document = XmlDocument.parse(body);
    final urls = <String, String>{};

    for (final entry in document.findAllElements('entry')) {
      final title = entry.getElement('title')?.innerText.trim();
      if (title != warningTitle) continue;
      final url = entry.getElement('id')?.innerText.trim();
      if (url == null || url.isEmpty) continue;
      // フィードは新しい順に並ぶので、先に入れた方を残す。
      urls.putIfAbsent(_officeOf(url), () => url);
    }
    return urls.values.toList();
  }

  static String _officeOf(String url) {
    final name = url.split('/').last;
    final parts = name.split('_');
    return parts.length >= 4 ? parts[3].split('.').first : name;
  }

  /// 1つの発表 XML から、区域ごとの警報を取り出す。
  List<DisasterEvent> parseReport(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      return const [];
    }

    final reportedAt = DateTime.tryParse(
      document.findAllElements('ReportDateTime').firstOrNull?.innerText ?? '',
    )?.toUtc();
    if (reportedAt == null) return const [];

    final section = document
        .findAllElements('Information')
        .where((node) => node.getAttribute('type') == areaSection)
        .firstOrNull;
    if (section == null) return const [];

    final events = <DisasterEvent>[];
    for (final item in section.findElements('Item')) {
      final event = _parseItem(item, reportedAt);
      if (event != null) events.add(event);
    }
    return events;
  }

  DisasterEvent? _parseItem(XmlElement item, DateTime reportedAt) {
    final area = item.findAllElements('Area').firstOrNull;
    final code = area?.getElement('Code')?.innerText.trim();
    if (code == null || code.isEmpty) return null;

    // Kind が並んでいるものが、その区域で今出ている警報。
    // 何も出ていない区域は Kind が空になる（解除された、の意味）。
    final active = [
      for (final kind in item.findElements('Kind'))
        if (kind.getElement('Code')?.innerText.trim() case final String warning
            when warning.isNotEmpty)
          JmaWarningSource.kindOf(warning),
    ];
    if (active.isEmpty) return null;

    // その区域で最も重い警報を、区域全体の深刻度とする。
    active.sort((a, b) => b.severity.level.compareTo(a.severity.level));
    final worst = active.first;

    final point = areaPoints[code];
    final areaName =
        point?.name ?? area?.getElement('Name')?.innerText.trim() ?? '区域$code';

    return DisasterEvent(
      // 発表中の警報。時刻は「いつ発表されたか」で、こちらは信用できる。
      isOngoing: true,
      // 発表内容が変われば ID も変わり、新しい通知として扱われる。
      id: 'jma-warn-$code-${active.map((w) => w.name).join(",")}',
      kind: EventKind.weatherWarning,
      severity: worst.severity,
      title: '$areaName ${worst.name}',
      subtitle: active.length > 1 ? active.map((w) => w.name).join('、') : null,
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
