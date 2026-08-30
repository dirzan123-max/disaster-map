import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../event_style.dart';

/// 「いまの設定なら、どの情報が通知されるか」を画面に出す帯。Web 版のみ。
///
/// Web 版には端末通知の仕組みが無いため、ここが通知の見本を兼ねる。
/// アプリ版では実際に通知が飛ぶので出さない。
/// 「通知対象 8件」とだけ出しても、何を指しているのか伝わらなかった。
class NotificationPreviewBanner extends StatelessWidget {
  const NotificationPreviewBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final events = state.notifiableEvents;
    if (events.isEmpty) return const SizedBox.shrink();

    final worst = events.reduce(
        (a, b) => a.severity.level >= b.severity.level ? a : b);
    final color = EventStyle.colorOf(worst.severity);
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '通知の見本（この条件なら${events.length}件が通知されます）',
                  style: theme.textTheme.labelSmall,
                ),
                Text(
                  '【${worst.severity.labelJa}】${worst.title}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
