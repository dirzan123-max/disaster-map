import 'dart:convert';

import 'package:disaster_map/domain/disaster_event.dart';
import 'package:disaster_map/domain/event_kind.dart';
import 'package:disaster_map/domain/severity.dart';
import 'package:disaster_map/domain/time_window.dart';
import 'package:disaster_map/features/notify/webhook_sender.dart';
import 'package:disaster_map/features/settings/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

DisasterEvent event({
  String id = 'test-1',
  EventKind kind = EventKind.earthquake,
  Severity severity = Severity.severe,
}) =>
    DisasterEvent(
      id: id,
      kind: kind,
      severity: severity,
      title: '宮城県沖 M6.2 最大震度5弱',
      occurredAt: DateTime.utc(2026, 8, 29, 0, 14),
      sourceName: '気象庁',
      areaName: '宮城県沖',
      sourceUrl: 'https://www.jma.go.jp/bosai/',
      details: const ['深さ 50km'],
    );

void main() {
  group('通知条件', () {
    /// 通知条件だけを差し替えた設定を作る。
    NotificationSettings settingsWith({
      Severity minimumSeverity = Severity.severe,
      Set<EventKind> kinds = const {EventKind.earthquake},
      bool enabled = true,
    }) =>
        NotificationSettings(
          enabled: enabled,
          rules: NotificationRules({
            for (final kind in kinds) kind: minimumSeverity,
          }),
          // 深刻度と種別の判定だけを見たいので、時刻では絞らない
          // （フィクスチャの時刻は固定なので、既定の24時間だと日が変わって落ちる）。
          timeWindow: TimeWindow.all,
        );

    test('深刻度が下限未満なら通知しない', () {
      final settings = settingsWith(minimumSeverity: Severity.severe);
      expect(
        settings.matches(event(severity: Severity.extreme)),
        isTrue,
      );
      expect(
        settings.matches(event(severity: Severity.severe)),
        isTrue,
      );
      expect(
        settings.matches(event(severity: Severity.moderate)),
        isFalse,
      );
    });

    test('対象外の種別は通知しない', () {
      final settings = settingsWith(
        minimumSeverity: Severity.moderate,
        kinds: {EventKind.earthquake},
      );
      expect(
        settings.matches(event(kind: EventKind.earthquake)),
        isTrue,
      );
      expect(
        settings.matches(event(kind: EventKind.wildfire)),
        isFalse,
      );
    });

    test('通知を切っていれば何も通らない', () {
      final settings = settingsWith(enabled: false);
      expect(
        settings.matches(event(severity: Severity.extreme)),
        isFalse,
      );
    });

    test('保存して読み直しても条件が変わらない', () {
      const original = NotificationSettings(
        rules: NotificationRules({
          EventKind.tsunami: Severity.moderate,
          EventKind.volcano: Severity.severe,
          EventKind.storm: Severity.extreme,
        }),
        webhookUrl: 'https://example.com/hook',
        webhookFormat: WebhookFormat.teams,
      );
      final restored = NotificationSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.rules.severityFor(EventKind.tsunami), Severity.moderate);
      expect(restored.rules.severityFor(EventKind.volcano), Severity.severe);
      expect(restored.rules.severityFor(EventKind.storm), Severity.extreme);
      expect(restored.webhookUrl, original.webhookUrl);
      expect(restored.webhookFormat, WebhookFormat.teams);
    });
  });

  group('Webhook のペイロード', () {
    test('Slack は text に本文が入る', () {
      final payload =
          WebhookSender.buildPayload(event(), WebhookFormat.slack);
      expect(payload['text'], contains('宮城県沖'));
      expect(payload['text'], contains('気象庁'));
    });

    test('Teams は MessageCard 形式で深刻度を色にする', () {
      final payload = WebhookSender.buildPayload(
          event(severity: Severity.extreme), WebhookFormat.teams);
      expect(payload['@type'], 'MessageCard');
      expect(payload['themeColor'], 'C62828');
    });

    test('Discord は content に本文が入る', () {
      final payload =
          WebhookSender.buildPayload(event(), WebhookFormat.discord);
      expect(payload['content'], contains('宮城県沖'));
    });

    test('Web で見せる curl は、そのまま実行できる形になっている', () {
      const settings = NotificationSettings(
        webhookUrl: 'https://hooks.slack.com/services/A/B/C',
      );
      final command = WebhookSender.curlCommand(event(), settings);
      expect(command, startsWith('curl -X POST'));
      expect(command, contains('https://hooks.slack.com/services/A/B/C'));
      expect(command, contains('Content-Type: application/json'));
    });
  });
}
