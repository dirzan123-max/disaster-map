import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/region.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import '../app_state.dart';
import '../event_style.dart';
import '../notify/notification_service.dart';
import '../notify/webhook_sender.dart';
import 'notification_settings.dart';

/// 通知の条件と連携先の設定。
///
/// Android は端末通知、Web は連携（Webhook）の見本という役割分担のため、
/// 画面もその2つに分けて説明を添えている。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _webhookController =
      TextEditingController(text: widget.state.settings.webhookUrl ?? '');

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  NotificationSettings get _settings => widget.state.settings;

  Future<void> _update(NotificationSettings settings) =>
      widget.state.updateSettings(settings);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('通知の設定')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            SwitchListTile(
              title: const Text('通知を受け取る'),
              subtitle: Text(
                kIsWeb
                    ? 'Web版では端末通知の代わりに、画面上に通知の見本を表示します'
                    : '15分ごとに自動で確認し、条件に合えば通知します',
              ),
              value: _settings.enabled,
              onChanged: (enabled) => _update(_settings.copyWith(enabled: enabled)),
            ),
            const Divider(),
            ListTile(
              title: const Text('通知の対象地域'),
              subtitle: const Text('画面の表示地域とは別に設定できます'),
              trailing: SegmentedButton<Region>(
                segments: const [
                  ButtonSegment(value: Region.japan, label: Text('日本')),
                  ButtonSegment(value: Region.world, label: Text('世界')),
                ],
                selected: {_settings.region},
                onSelectionChanged: (selection) =>
                    _update(_settings.copyWith(region: selection.first)),
              ),
            ),
            ListTile(
              title: const Text('通知する深刻度'),
              subtitle: Text('${_settings.minimumSeverity.labelJa}以上のときに通知します'),
              trailing: DropdownButton<Severity>(
                value: _settings.minimumSeverity,
                onChanged: (severity) {
                  if (severity != null) {
                    _update(_settings.copyWith(minimumSeverity: severity));
                  }
                },
                items: [
                  for (final severity in Severity.values)
                    DropdownMenuItem(
                      value: severity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: EventStyle.colorOf(severity),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(severity.labelJa),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final kind in EventKind.values)
                    FilterChip(
                      avatar: Icon(EventStyle.iconOf(kind), size: 18),
                      label: Text(kind.labelJa),
                      selected: _settings.kinds.contains(kind),
                      onSelected: (selected) {
                        final kinds = Set<EventKind>.from(_settings.kinds);
                        if (selected) {
                          kinds.add(kind);
                        } else {
                          kinds.remove(kind);
                        }
                        // すべて外すと通知が一切来なくなるため、最低1つは残す。
                        if (kinds.isEmpty) return;
                        _update(_settings.copyWith(kinds: kinds));
                      },
                    ),
                ],
              ),
            ),
            if (!kIsWeb) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('テスト通知を出す'),
                subtitle: const Text('15分の自動確認を待たずに、通知が届くかを確かめます'),
                onTap: () async {
                  final granted =
                      await NotificationService.instance.requestPermission();
                  await NotificationService.instance.showTest();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(granted
                          ? 'テスト通知を送りました'
                          : '通知が許可されていません。端末の設定を確認してください'),
                    ),
                  );
                },
              ),
            ],
            const Divider(),
            _WebhookSection(
              state: widget.state,
              controller: _webhookController,
              onChanged: (settings) => _update(settings),
            ),
          ],
        ),
      ),
    );
  }
}

/// 業務チャットへの連携設定。
class _WebhookSection extends StatelessWidget {
  const _WebhookSection({
    required this.state,
    required this.controller,
    required this.onChanged,
  });

  final AppState state;
  final TextEditingController controller;
  final ValueChanged<NotificationSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings;
    final theme = Theme.of(context);
    final sample = state.notifiableEvents.firstOrNull ??
        state.visibleEvents.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          title: Text('業務チャットへの連携'),
          subtitle: Text('対策本部のチャンネルに履歴として残したい場合に設定します'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<WebhookFormat>(
                segments: [
                  for (final format in WebhookFormat.values)
                    ButtonSegment(value: format, label: Text(format.label)),
                ],
                selected: {settings.webhookFormat},
                onSelectionChanged: (selection) =>
                    onChanged(settings.copyWith(webhookFormat: selection.first)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Incoming Webhook の URL',
                  hintText: 'https://hooks.slack.com/services/...',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) =>
                    onChanged(settings.copyWith(webhookUrl: value.trim())),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => onChanged(
                      settings.copyWith(webhookUrl: controller.text.trim())),
                  child: const Text('保存'),
                ),
              ),
              if (kIsWeb)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ブラウザからは Slack などの Webhook へ直接送信できません'
                    '（送信先が CORS を許可していないため）。'
                    'Web版では下の送信内容を確認し、実際の送信はアプリ版か、'
                    '同梱の GitHub Actions ワークフローで行ってください。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (sample != null) ...[
                const SizedBox(height: 16),
                Text('送信される内容（実データ）', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                _PayloadPreview(
                  text: WebhookSender.curlCommand(sample, settings),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PayloadPreview extends StatelessWidget {
  const _PayloadPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('コピーしました')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('コピー'),
            ),
          ),
        ],
      ),
    );
  }
}
