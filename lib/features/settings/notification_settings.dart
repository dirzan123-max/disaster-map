import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/region.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';

/// 通知を出す条件と、業務システムへの連携先。
///
/// Android のバックグラウンド処理からも読むため、
/// UI の状態とは切り離して端末に保存する。
class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.region = Region.japan,
    this.minimumSeverity = Severity.severe,
    this.kinds = const {
      EventKind.earthquake,
      EventKind.tsunami,
      EventKind.weatherWarning,
      EventKind.volcano,
    },
    this.webhookUrl,
    this.webhookFormat = WebhookFormat.slack,
  });

  final bool enabled;

  /// 通知の対象地域。画面の表示地域とは独立して設定できる
  /// （世界の地図を見ながら、通知は日本だけ受け取る、といった使い方のため）。
  final Region region;

  /// この深刻度以上のときだけ通知する。
  final Severity minimumSeverity;

  /// 通知したい災害の種類。
  final Set<EventKind> kinds;

  /// Slack / Teams / Discord の Incoming Webhook URL。
  /// 設定されていれば、端末通知と同時に業務チャンネルへも送る。
  final String? webhookUrl;

  final WebhookFormat webhookFormat;

  bool get hasWebhook => (webhookUrl ?? '').trim().isNotEmpty;

  /// このイベントが通知条件を満たすか。
  ///
  /// 端末通知・Webhook・Web版のプレビューがすべてこの判定を共有するため、
  /// 「画面に見えている条件」と「実際に飛ぶ通知」が必ず一致する。
  bool matches(DisasterEvent event) =>
      enabled &&
      kinds.contains(event.kind) &&
      event.severity.level >= minimumSeverity.level;

  NotificationSettings copyWith({
    bool? enabled,
    Region? region,
    Severity? minimumSeverity,
    Set<EventKind>? kinds,
    String? webhookUrl,
    WebhookFormat? webhookFormat,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        region: region ?? this.region,
        minimumSeverity: minimumSeverity ?? this.minimumSeverity,
        kinds: kinds ?? this.kinds,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        webhookFormat: webhookFormat ?? this.webhookFormat,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'region': region.name,
        'minimumSeverity': minimumSeverity.level,
        'kinds': kinds.map((kind) => kind.name).toList(),
        'webhookUrl': webhookUrl,
        'webhookFormat': webhookFormat.name,
      };

  static NotificationSettings fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        enabled: json['enabled'] as bool? ?? true,
        region: Region.values.firstWhere(
          (region) => region.name == json['region'],
          orElse: () => Region.japan,
        ),
        minimumSeverity:
            Severity.fromLevel((json['minimumSeverity'] as num?)?.toInt() ?? 3),
        kinds: (json['kinds'] as List? ?? const [])
            .map((name) => EventKind.values
                .where((kind) => kind.name == name)
                .firstOrNull)
            .nonNulls
            .toSet(),
        webhookUrl: json['webhookUrl'] as String?,
        webhookFormat: WebhookFormat.values.firstWhere(
          (format) => format.name == json['webhookFormat'],
          orElse: () => WebhookFormat.slack,
        ),
      );

  static const String _storageKey = 'notification_settings';

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(toJson()));
  }

  static Future<NotificationSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = preferences.getString(_storageKey);
    if (payload == null) return const NotificationSettings();
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return const NotificationSettings();
      final settings = fromJson(decoded);
      // 種別を全部外した設定は通知が一切飛ばず事故のもとなので、既定へ戻す。
      return settings.kinds.isEmpty ? const NotificationSettings() : settings;
    } on FormatException {
      return const NotificationSettings();
    }
  }
}

/// Webhook のペイロード形式。業務で使われる3つに対応する。
enum WebhookFormat {
  slack,
  teams,
  discord;

  String get label => switch (this) {
        WebhookFormat.slack => 'Slack',
        WebhookFormat.teams => 'Microsoft Teams',
        WebhookFormat.discord => 'Discord',
      };
}
