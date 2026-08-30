import 'package:flutter/material.dart';

import '../core/time_format.dart';
import '../domain/severity.dart';
import '../domain/time_window.dart';
import 'app_state.dart';
import 'detail/event_detail_sheet.dart';
import 'event_style.dart';
import 'list/event_list.dart';
import 'map/disaster_map_view.dart';
import 'notify/desktop_monitor.dart';
import 'notify/notification_preview.dart';
import 'settings/settings_page.dart';
import 'settings/time_window_sheet.dart';

/// 地図・一覧・絞り込みをまとめた主画面。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, this.desktop});

  final AppState state;

  /// パソコンで開いている間の監視。設定を変えたときに入切を合わせる。
  final DesktopMonitor? desktop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('災害情報マップ'),
            actions: [
              IconButton(
                tooltip: '最新の情報を取得',
                onPressed: state.loading ? null : state.refresh,
                icon: state.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '設定',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SettingsPage(state: state, desktop: desktop),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
            bottom: PreferredSize(
              // 種別と絞り込みの2段。文字が折り返して潰れない高さを確保する。
              preferredSize: const Size.fromHeight(96),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 48, child: _KindFilter(state: state)),
                  SizedBox(height: 48, child: _ConditionBar(state: state)),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              _StatusBar(state: state),
              Expanded(
                child: Stack(
                  children: [
                    DisasterMapView(state: state),
                    _EventSheet(state: state),
                    if (state.selected != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: EventDetailSheet(
                          event: state.selected!,
                          onClose: () => state.select(null),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 表示する災害種別。取得できた種別から1つだけ選ぶ。
///
/// 複数選択にすると「今どの情報を見ているのか」が分かりにくく、
/// 地図のグレー表示（取得できない範囲）も種別ごとに決まるため、
/// 1種別ずつ切り替える形にしている。
class _KindFilter extends StatelessWidget {
  const _KindFilter({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final kinds = state.availableKinds;

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final kind in kinds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
            child: ChoiceChip(
              avatar: Icon(EventStyle.iconOf(kind), size: 18),
              label: Text(kind.labelJa, softWrap: false),
              selected: state.selectedKind == kind,
              onSelected: (_) => state.selectKind(kind),
            ),
          ),
      ],
    );
  }
}

/// 深刻度と期間の絞り込み。
///
/// 国の指定は「しょっちゅう変えるものではない」ので、ここではなく設定画面に置く。
/// 絞り込み中かどうかは下の帯に出す。
class _ConditionBar extends StatelessWidget {
  const _ConditionBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        _ConditionButton(
          icon: Icons.warning_amber,
          label: '深刻度',
          value: '${state.minimumSeverity.labelJa}以上',
          onPressed: () => _showSeverityMenu(context),
        ),
        _ConditionButton(
          icon: Icons.history,
          label: '期間',
          value: state.timeWindowLabel,
          onPressed: () => _showTimeMenu(context),
        ),
      ],
    );
  }

  /// 期間メニューの1行説明。上限が何で決まっているかをその場で示す。
  static String _menuNote(AppState state) {
    final kind = state.selectedKind;
    final limit = state.historyLimit;
    if (kind == null) return '発生・発表からの経過時間で絞り込みます';
    if (limit == null) {
      // 気象警報は今出ているものだけが配信され、時刻は最終更新時刻を指す。
      return '${kind.labelJa}は今出ているものだけが配信されます。'
          'いつ更新された警報かで絞り込みます';
    }
    return '${kind.labelJa}は最大${TimeWindow.spanLabel(limit)}ぶんまで'
        'さかのぼれます';
  }

  Future<void> _showSeverityMenu(BuildContext context) async {
    final selected = await showModalBottomSheet<Severity>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('深刻度の下限'),
              subtitle: Text('選んだ段階より軽い情報は地図と一覧に出しません'),
            ),
            for (final severity in Severity.filterOptions)
              ListTile(
                onTap: () => Navigator.of(context).pop(severity),
                selected: state.minimumSeverity == severity,
                leading: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: EventStyle.colorOf(severity),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text('${severity.labelJa}以上'),
                trailing: state.minimumSeverity == severity
                    ? const Icon(Icons.check)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (selected != null) state.setMinimumSeverity(selected);
  }

  Future<void> _showTimeMenu(BuildContext context) async {
    final selected = await showTimeWindowSheet(
      context,
      current: state.timeWindow,
      limit: state.historyLimit,
      note: _menuNote(state),
    );
    if (selected != null) await state.setTimeWindow(selected);
  }
}

class _ConditionButton extends StatelessWidget {
  const _ConditionButton({
    required this.icon,
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String value;

  /// null なら押せない（その種別では意味を持たない絞り込み）。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text('$label: $value', softWrap: false),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

/// 最終更新・取得失敗・キャッシュ表示を伝える帯。
///
/// 災害時に一番困るのは「いつの情報か分からない」ことなので、
/// 鮮度と欠落は常に画面に出しておく。
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    final theme = Theme.of(context);
    if (snapshot == null) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    // 取得中はまだ失敗と決まっていないので、警告色にはしない。
    final warning =
        !state.loading && (snapshot.fromCache || snapshot.hasFailures);
    final background = warning
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;

    // 取得はできているのに中身が古い、という状態を黙って0件にしない。
    final staleSince = state.staleSince;
    if (staleSince != null && !state.loading) {
      return Container(
        width: double.infinity,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${state.selectedKind?.labelJa ?? ''}の配信が止まっています'
                '（最新 ${formatLocalFull(staleSince)}）',
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            state.loading
                ? Icons.downloading
                : (warning ? Icons.warning_amber : Icons.schedule),
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (state.loading)
                  '最新の情報を取得しています…'
                else if (snapshot.fromCache)
                  '通信できないため保存済みの情報を表示しています'
                else
                  '最終更新 ${formatElapsed(snapshot.fetchedAt)}',
                '${state.visibleEvents.length}件',
                // 国の指定は設定画面にあるため、効いていることをここで知らせる。
                if (!state.countryFilter.isEmpty)
                  '国: ${state.countryFilter.countryCount}か国に限定中',
                if (snapshot.hasFailures && !state.loading)
                  '取得失敗: ${snapshot.failures.map((f) => f.sourceName).join("、")}',
              ].join(' ・ '),
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一覧の見出し。何のための一覧なのかをここで示す。
///
/// ピンを見れば分かるものが並ぶだけに見えるが、
/// 座標を持たない情報（津波予報区など）は地図に出せないため、
/// 一覧が唯一の出口になる。ピンが重なって潰れるときにも要る。
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = state.visibleEvents;
    final withoutLocation = events.where((event) => !event.hasLocation).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '一覧（新しい順）・${events.length}件',
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (withoutLocation > 0)
            Text(
              '地図に出せない情報 $withoutLocation件',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

/// 地図の下から引き上げるイベント一覧。
///
/// つまみ（横棒）はスクロール領域の外にあるため、そのままでは指で引いても
/// 何も起きず、一覧の上をなぞったときだけ動く。位置がずれて感じる原因なので、
/// つまみ自体にドラッグとタップを付けている。
class _EventSheet extends StatefulWidget {
  const _EventSheet({required this.state});

  final AppState state;

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  static const double _minSize = 0.1;
  static const double _collapsedSize = 0.2;
  static const double _expandedSize = 0.85;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// つまみを上下に引いた分だけシートの高さを変える。
  void _dragHandle(double deltaPixels, double availableHeight) {
    if (!_controller.isAttached || availableHeight <= 0) return;
    final size = _controller.size - deltaPixels / availableHeight;
    _controller.jumpTo(size.clamp(_minSize, _expandedSize));
  }

  /// つまみを叩いたら開閉する。
  void _toggle() {
    if (!_controller.isAttached) return;
    final target = _controller.size > (_collapsedSize + _expandedSize) / 2
        ? _collapsedSize
        : _expandedSize;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return DraggableScrollableSheet(
          controller: _controller,
          initialChildSize: _collapsedSize,
          minChildSize: _minSize,
          maxChildSize: _expandedSize,
          builder: (context, scrollController) {
            return Material(
              elevation: 6,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  GestureDetector(
                    // 横棒そのものは細いので、周りの余白ごと受け取る。
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggle,
                    onVerticalDragUpdate: (details) =>
                        _dragHandle(details.delta.dy, constraints.maxHeight),
                    child: SizedBox(
                      height: 28,
                      width: double.infinity,
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _SheetHeader(state: widget.state),
                      NotificationPreviewBanner(state: widget.state),
                  Expanded(
                    child: EventList(
                      state: widget.state,
                      controller: scrollController,
                      onSelect: widget.state.select,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
