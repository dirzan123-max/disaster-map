import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/time_format.dart';
import '../../domain/disaster_event.dart';
import '../event_style.dart';

/// 1件の詳細。出典と発表時刻を必ず添える。
///
/// 情報の出どころが辿れないと、いざというときに使えないため、
/// 「どこが出した情報か」「いつ時点か」「原文はどこか」を必ず並べている。
class EventDetailSheet extends StatelessWidget {
  const EventDetailSheet({super.key, required this.event, required this.onClose});

  final DisasterEvent event;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.colorOf(event.severity);
    final theme = Theme.of(context);

    // 下から引き出す一覧の上に重なるため、同じ地の色だと境目が見えない。
    // 一段濃い面と、上辺の線・影で「別の物が乗っている」ことを示す。
    return Material(
      elevation: 16,
      color: theme.colorScheme.surfaceContainerHighest,
      shadowColor: theme.colorScheme.shadow,
      shape: Border(
        top: BorderSide(color: theme.colorScheme.outline, width: 2),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color,
                    child: Icon(
                      EventStyle.iconOf(event.kind),
                      color: EventStyle.onColorOf(event.severity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event.title, style: theme.textTheme.titleMedium),
                        Text(
                          '${event.kind.labelJa}・${event.severity.labelJa}',
                          style: theme.textTheme.labelMedium?.copyWith(color: color),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                    tooltip: '閉じる',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                event.isOngoing
                    // 配信元が「今出ている」として配っているもの。
                    // 時刻は発表・更新された時刻であって、発生時刻ではない。
                    ? '発表中・最終更新 ${formatLocalFull(event.occurredAt)}'
                        '（${formatElapsed(event.occurredAt)}）'
                    : '発表・発生: ${formatLocalFull(event.occurredAt)}'
                        '（${formatElapsed(event.occurredAt)}）',
                style: theme.textTheme.bodySmall,
              ),
              if (event.details.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final detail in event.details)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text('・$detail',
                                style: theme.textTheme.bodySmall),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '出典: ${event.sourceName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (event.sourceUrl != null)
                    TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(event.sourceUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('原文を見る'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
