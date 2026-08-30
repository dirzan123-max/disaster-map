import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import '../app_state.dart';
import '../event_style.dart';
import '../notify/desktop_monitor.dart';
import '../notify/notification_service.dart';
import '../notify/realtime_monitor.dart';
import '../map/map_style.dart';
import '../notify/webhook_sender.dart';
import '../tutorial/tutorial_page.dart';
import '../../domain/time_window.dart';
import 'country_filter_page.dart';
import 'notification_settings.dart';
import 'time_window_sheet.dart';

/// 通知の条件と、画面と共通の絞り込み。
///
/// 日本と世界では出てくる情報がまるで違う（日本は震度つきの地震と気象警報、
/// 世界は M4 以上の地震と台風・山火事）。同じ条件を使い回すとどちらかが
/// 必ず不都合になるため、通知の条件は地域ごとに分けて、両方同時に監視できる。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.state, this.desktop});

  final AppState state;

  /// パソコンで開いている間の監視。リアルタイム監視の入切に使う。
  final DesktopMonitor? desktop;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _webhookController =
      TextEditingController(text: widget.state.settings.webhookUrl ?? '');

  /// 端末側で通知が許可されているか。確認前は null。
  bool? _permitted;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    if (kIsWeb) return;
    final permitted = await NotificationService.instance.isPermitted();
    if (mounted) setState(() => _permitted = permitted);
  }

  /// 許可を求める。すでに拒否されていると Android は何も出さないため、
  /// そのときは端末の設定から変える必要があることを伝える。
  Future<void> _requestPermission() async {
    final granted = await NotificationService.instance.requestPermission();
    await _refreshPermission();
    if (!mounted || granted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '許可されませんでした。端末の「設定 > アプリ > 災害情報マップ > 通知」から'
          '許可してください',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }

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
        appBar: AppBar(title: const Text('設定')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // アプリ内で ON にしていても、端末が許可していなければ鳴らない。
            // 気づけないと「通知が来ない」で終わるので、ここで直せるようにする。
            if (_permitted == false)
              _PermissionBanner(onRequest: _requestPermission),
            SwitchListTile(
              title: const Text('通知を受け取る'),
              subtitle: Text(_checkIntervalNote()),
              value: _settings.enabled,
              onChanged: (enabled) =>
                  _update(_settings.copyWith(enabled: enabled)),
            ),
            if (!kIsWeb)
              SwitchListTile(
                secondary: const Icon(Icons.bolt),
                title: const Text('リアルタイム監視'),
                subtitle: Text(_realtimeNote()),
                isThreeLine: true,
                value: _settings.enabled && _settings.realtime,
                onChanged: _settings.enabled ? _setRealtime : null,
              ),
            const Divider(),
            const _SectionTitle('通知する種類と深刻度'),
            if (_settings.enabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final kind in NotificationRules.availableKinds)
                      _KindRow(
                        kind: kind,
                        severity: _settings.rules.severityFor(kind),
                        onChanged: (severity) => _update(
                          _settings.copyWith(
                            rules: _settings.rules.withKind(kind, severity),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(),
            const _SectionTitle('通知する範囲'),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('古い情報は通知しない'),
              subtitle: Text(_ageSummary(_settings.timeWindow)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selected = await showTimeWindowSheet(
                  context,
                  current: _settings.timeWindow,
                  note: '発生・発表からこの時間以内のものだけ通知します。'
                      '今出ている警報や、続いている山火事・台風は、'
                      '期間に関わらず通知します',
                );
                if (selected != null) {
                  await widget.state.setTimeWindow(selected);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('対象の国・地域'),
              subtitle: Text(_countrySummary()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CountryFilterPage(state: widget.state),
                ),
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
            const _SectionTitle('地図の見え方'),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('世界地図の中心'),
              subtitle: Text(widget.state.worldCenter.description),
              trailing: DropdownButton<WorldCenter>(
                value: widget.state.worldCenter,
                onChanged: (center) {
                  if (center != null) widget.state.setWorldCenter(center);
                },
                items: [
                  for (final center in WorldCenter.values)
                    DropdownMenuItem(value: center, child: Text(center.label)),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('使い方とデータの範囲'),
              subtitle: const Text('どの情報をどこまで取れているかも、ここで確認できます'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
              ),
            ),
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

  /// 自動確認の説明。仕組みが環境で違うので、書き分ける。
  String _checkIntervalNote() {
    if (kIsWeb) {
      return 'Web版では端末通知の代わりに、画面上に通知の見本を表示します';
    }
    if (DesktopMonitor.isSupported) {
      final minutes = DesktopMonitor.interval.inMinutes;
      return 'このアプリを開いている間、$minutes分ごとに自動で確認し、'
          '条件に合えば通知します。閉じている間は確認しません';
    }
    return '15分ごとに自動で確認し、条件に合えば通知します。'
        '15分は Android が許す最短の間隔で、これより短くはできません。'
        '実際には端末の省電力機能により、画面を消している間は'
        '間隔が延びることがあります';
  }

  /// リアルタイム監視の説明。パソコンでは常駐の代償が無い。
  String _realtimeNote() {
    if (DesktopMonitor.isSupported) {
      return '地震の発表を待たずに、数秒で受け取ります。'
          'このアプリを開いている間だけ動きます。'
          '対象は地震・津波だけで、気象警報などは自動確認のままです';
    }
    return '地震の発表を待たずに、数秒で受け取ります。'
        '常駐するため通知バーに「監視中」が出たままになり、'
        '電池の消費も増えます。'
        '対象は地震・津波だけで、気象警報などは15分ごとの確認のままです';
  }

  /// 常駐監視の入切。
  ///
  /// OS のサービスを触るのはこの画面だけにしている。
  /// [AppState] から呼ぶと、画面のない場所（テストなど）でも
  /// ネイティブの呼び出しに入ってしまうため。
  Future<void> _setRealtime(bool on) async {
    await _update(_settings.copyWith(realtime: on));

    // パソコンは常駐サービスが要らない。アプリ自身がつなぐ。
    if (DesktopMonitor.isSupported) {
      await widget.desktop?.settingsChanged();
      return;
    }

    final started = await RealtimeMonitor.applySetting(widget.state.settings);
    if (!mounted || started || !on) return;
    // 権限や機種の制約で常駐できないことがある。黙って失敗しない。
    await _update(_settings.copyWith(realtime: false));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('常駐監視を開始できませんでした。通知の許可を確認してください')),
    );
  }

  /// 通知の対象になる「新しさ」の説明。
  ///
  /// 通知では下限（「1時間前から」）を使わないため、上限だけで書く。
  String _ageSummary(TimeWindow window) {
    final limit = window.maxAge;
    if (limit == null) {
      return '古さでは絞らずに通知します。地図の「期間」と共通の設定です';
    }
    return '発生・発表から${TimeWindow.spanLabel(limit)}以内のものだけ通知します。'
        '今出ている警報や続いている災害は、それより古くても通知します。'
        '地図の「期間」と共通の設定です';
  }

  String _countrySummary() {
    final countries = _settings.countries;
    if (countries.isEmpty) return '全世界（登録なし）。地図の絞り込みと共通です';
    return countries.perKind
        ? '種別ごとに指定中（合わせて${countries.countryCount}か国）'
        : 'まとめて${countries.countryCount}か国を指定中';
  }
}

/// 端末の通知が許可されていないことを知らせ、その場で許可を求める。
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_off_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '端末が通知を許可していないため、条件に合っても鳴りません',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onRequest,
              child: const Text('通知を許可する'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 1種別ぶんの通知条件。「通知しない」も同じ並びから選べるようにしている。
class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.kind,
    required this.severity,
    required this.onChanged,
  });

  final EventKind kind;

  /// 通知する下限。null は「通知しない」。
  final Severity? severity;
  final ValueChanged<Severity?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 「山火事は米国だけ」のような但し書きを、選ぶその場に出す。
    final note = NotificationRules.areaNoteFor(kind);

    return Row(
      children: [
        Icon(
          EventStyle.iconOf(kind),
          size: 18,
          color: severity == null ? theme.disabledColor : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note == null ? kind.labelJa : '${kind.labelJa}（$note）',
            style: severity == null
                ? theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.disabledColor)
                : theme.textTheme.bodyMedium,
          ),
        ),
        DropdownButton<Severity?>(
          value: severity,
          underline: const SizedBox.shrink(),
          onChanged: onChanged,
          items: [
            const DropdownMenuItem<Severity?>(
              value: null,
              child: Text('通知しない'),
            ),
            for (final option in Severity.notifyOptions)
              DropdownMenuItem<Severity?>(
                value: option,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: EventStyle.colorOf(option),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      option == Severity.extreme
                          ? '重大のみ'
                          : '${option.labelJa}以上',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: theme.colorScheme.primary),
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
    final sample =
        state.notifiableEvents.firstOrNull ?? state.visibleEvents.firstOrNull;

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
