import 'package:flutter/material.dart';

import '../../core/time_format.dart';
import '../../domain/disaster_event.dart';
import '../../domain/time_window.dart';
import '../app_state.dart';
import '../event_style.dart';

/// 発生時刻の新しい順に並べたイベント一覧。
///
/// 地図に出せない情報（座標を持たない津波予報区など）も必ずここに現れる。
class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.state,
    required this.onSelect,
    this.controller,
  });

  final AppState state;
  final ValueChanged<DisasterEvent> onSelect;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final events = state.visibleEvents;
    if (events.isEmpty) {
      return ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  state.loading ? '取得中です…' : '条件に合う情報はありません',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                // 絞り込みのせいなのか、配信が止まっているのかを分ける。
                if (!state.loading && state.staleSince != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '配信元の更新が ${formatLocalFull(state.staleSince!)} で'
                    '止まっています',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                // 絞り込みで消えているのか、そもそも無いのかが分からないと
                // 「壊れている」に見える。次の一手をその場に置く。
                if (!state.loading && !state.timeWindow.isUnbounded) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${state.timeWindow.label}で絞り込んでいます',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => state.setTimeWindow(TimeWindow.all),
                    child: const Text('期間の絞り込みを外す'),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: controller,
      itemCount: events.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        return EventTile(
          event: event,
          selected: state.selected?.id == event.id,
          onTap: () => onSelect(event),
        );
      },
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({
    super.key,
    required this.event,
    required this.onTap,
    this.selected = false,
  });

  final DisasterEvent event;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.colorOf(event.severity);
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color,
        child: Icon(
          EventStyle.iconOf(event.kind),
          color: EventStyle.onColorOf(event.severity),
          size: 20,
        ),
      ),
      title: Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          // 継続中のものは時刻が「最後に発表・観測された時刻」でしかない。
          event.isOngoing
              ? '${formatLocal(event.occurredAt)} 更新'
              : formatLocal(event.occurredAt),
          if (event.subtitle != null && event.subtitle!.isNotEmpty)
            event.subtitle!,
        ].join(' ・ '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            event.severity.labelJa,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold),
          ),
          if (event.isOngoing)
            // 配信元が「今出ている」として配っているもの。
            // 実際に続いているかは配信元の更新次第なので、時刻も併記している。
            Text('発表中', style: Theme.of(context).textTheme.labelSmall)
          else if (!event.hasLocation)
            Text('地図なし', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
