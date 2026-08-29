import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/time_format.dart';
import '../../domain/disaster_event.dart';
import '../settings/notification_settings.dart';

/// 業務チャットへの連携（Slack / Teams / Discord の Incoming Webhook）。
///
/// BCP の現場では「担当者の端末に通知が出る」だけでは足りず、
/// 対策本部のチャンネルに履歴として残ることが求められる。
/// ここはその連携部分で、ペイロードの組み立てと送信を分けてある。
///
/// なお Web 版（ブラウザ）からは、これらの Webhook が CORS を許可していないため
/// 直接送信できない。Web では [curlCommand] で送信内容を提示し、
/// 実送信はアプリ版か、同梱の GitHub Actions ワークフローに任せる。
class WebhookSender {
  const WebhookSender({this.client});

  final http.Client? client;

  /// 送信するペイロードを組み立てる。送信せずに中身を見せたいときにも使う。
  static Map<String, dynamic> buildPayload(
    DisasterEvent event,
    WebhookFormat format,
  ) {
    final headline = '【${event.severity.labelJa}】${event.title}';
    final body = [
      '種別: ${event.kind.labelJa}',
      '発表: ${formatLocalFull(event.occurredAt)}',
      if (event.areaName != null) '地域: ${event.areaName}',
      '出典: ${event.sourceName}',
      if (event.sourceUrl != null) event.sourceUrl!,
    ].join('\n');

    return switch (format) {
      // Slack: text だけでも届く。装飾は blocks で足せる。
      WebhookFormat.slack => {
          'text': '$headline\n$body',
        },
      // Teams: MessageCard 形式。themeColor で深刻度を色で示す。
      WebhookFormat.teams => {
          '@type': 'MessageCard',
          '@context': 'https://schema.org/extensions',
          'summary': headline,
          'themeColor': _teamsColor(event),
          'title': headline,
          'text': body.replaceAll('\n', '\n\n'),
        },
      // Discord: content が本文。
      WebhookFormat.discord => {
          'content': '$headline\n$body',
        },
    };
  }

  static String _teamsColor(DisasterEvent event) => switch (event.severity.level) {
        4 => 'C62828',
        3 => 'EF6C00',
        2 => 'F9A825',
        _ => '546E7A',
      };

  /// Web 版で提示する送信コマンド。実際に業務環境で試せる形にしておく。
  static String curlCommand(
    DisasterEvent event,
    NotificationSettings settings,
  ) {
    final payload = jsonEncode(buildPayload(event, settings.webhookFormat));
    final url = settings.webhookUrl ?? 'https://hooks.slack.com/services/XXX/YYY/ZZZ';
    return "curl -X POST -H 'Content-Type: application/json' \\\n"
        "  -d '$payload' \\\n"
        '  $url';
  }

  /// 実際に送信する（Android 版と GitHub Actions 用）。
  ///
  /// 失敗しても端末通知は既に出ているため、例外は投げずに結果だけ返す。
  Future<bool> send(DisasterEvent event, NotificationSettings settings) async {
    if (!settings.hasWebhook) return false;
    final target = Uri.tryParse(settings.webhookUrl!.trim());
    if (target == null) return false;

    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .post(
            target,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(buildPayload(event, settings.webhookFormat)),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    } finally {
      if (client == null) httpClient.close();
    }
  }
}
