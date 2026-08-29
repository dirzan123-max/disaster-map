import 'package:flutter/material.dart';

import '../core/region.dart';
import '../core/time_format.dart';
import '../domain/severity.dart';
import 'app_state.dart';
import 'detail/event_detail_sheet.dart';
import 'event_style.dart';
import 'list/event_list.dart';
import 'map/disaster_map_view.dart';
import 'notify/notification_preview.dart';
import 'settings/settings_page.dart';

/// 地図・一覧・絞り込みをまとめた主画面。
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

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
                tooltip: '通知の設定',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(state: state),
                  ),
                ),
                icon: const Icon(Icons.notifications_outlined),
              ),
              IconButton(
                tooltip: 'このアプリについて',
                onPressed: () => _showAbout(context),
                icon: const Icon(Icons.info_outline),
              ),
            ],
            bottom: PreferredSize(
              // 地域切替とフィルタの2段。文字が折り返して潰れない高さを確保する。
              preferredSize: const Size.fromHeight(116),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(height: 56, child: _RegionSwitch(state: state)),
                  SizedBox(height: 56, child: _FilterBar(state: state)),
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

  void _showAbout(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('このアプリについて'),
        content: const SingleChildScrollView(
          child: Text(
            '気象庁・USGS・NASA が公開している情報を取得し、地図に重ねて表示します。\n\n'
            '本アプリは状況把握を助ける補助的なツールです。'
            '避難などの判断は、必ず自治体や気象庁の公式発表を優先してください。\n\n'
            '出典\n'
            '・気象庁（地震・津波・気象警報・噴火警報）\n'
            '・P2P地震情報（気象庁発表の配信）\n'
            '・USGS Earthquake Hazards Program\n'
            '・NASA EONET\n'
            '・地理院タイル（国土地理院）\n'
            '・© OpenStreetMap contributors © CARTO',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}

/// 日本版 / 世界版の切り替え。
class _RegionSwitch extends StatelessWidget {
  const _RegionSwitch({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SegmentedButton<Region>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: Region.japan,
            label: Text('日本'),
            icon: Icon(Icons.flag_outlined),
          ),
          ButtonSegment(
            value: Region.world,
            label: Text('世界'),
            icon: Icon(Icons.public),
          ),
        ],
        selected: {state.region},
        onSelectionChanged: (selection) => state.setRegion(selection.first),
      ),
    );
  }
}

/// 表示する災害種別と、深刻度の下限。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // その地域で実際に出てくる種別だけを並べる（空の絞り込みを作らない）。
    final availableKinds = {
      for (final event in state.snapshot?.events ?? const []) event.kind,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));

    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        for (final kind in availableKinds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            child: FilterChip(
              avatar: Icon(EventStyle.iconOf(kind), size: 18),
              label: Text(
                state.region.useEnglish ? kind.labelEn : kind.labelJa,
                softWrap: false,
                overflow: TextOverflow.visible,
              ),
              selected: state.visibleKinds.contains(kind),
              onSelected: (_) => state.toggleKind(kind),
            ),
          ),
        const VerticalDivider(width: 16),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: DropdownButton<Severity>(
            value: state.minimumSeverity,
            underline: const SizedBox.shrink(),
            onChanged: (severity) {
              if (severity != null) state.setMinimumSeverity(severity);
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
                      Text('${severity.labelJa}以上'),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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

    final warning = snapshot.fromCache || snapshot.hasFailures;
    final background = warning
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(warning ? Icons.warning_amber : Icons.schedule, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (snapshot.fromCache)
                  '通信できないため保存済みの情報を表示しています'
                else
                  '最終更新 ${formatElapsed(snapshot.fetchedAt)}',
                '${state.visibleEvents.length}件',
                if (snapshot.hasFailures)
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

/// 地図の下から引き上げるイベント一覧。
class _EventSheet extends StatelessWidget {
  const _EventSheet({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.28,
      minChildSize: 0.1,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Material(
          elevation: 6,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              NotificationPreviewBanner(state: state),
              Expanded(
                child: EventList(
                  state: state,
                  controller: scrollController,
                  onSelect: state.select,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
