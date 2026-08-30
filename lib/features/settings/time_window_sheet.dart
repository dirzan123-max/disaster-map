import 'package:flutter/material.dart';

import '../../domain/time_window.dart';

/// さかのぼる期間を選ぶシート。地図の絞り込みと通知設定で共有する。
///
/// [limit] を渡すと、そこまでの選択肢しか出さない。
/// 配信されていない長さを選ばせると、絞り込みのせいで出ないのか
/// 情報が無いのか分からなくなるため。
Future<TimeWindow?> showTimeWindowSheet(
  BuildContext context, {
  required TimeWindow current,
  required String note,
  Duration? limit,
}) {
  String labelOf(TimeWindow window) {
    if (!window.isUnbounded || limit == null) return window.label;
    return 'すべて（最大${TimeWindow.spanLabel(limit)}）';
  }

  return showModalBottomSheet<TimeWindow>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('さかのぼる期間'),
              subtitle: Text(note),
            ),
            for (final window in TimeWindow.presetsWithin(limit))
              ListTile(
                onTap: () => Navigator.of(context).pop(window),
                selected: current == window,
                title: Text(labelOf(window)),
                trailing:
                    current == window ? const Icon(Icons.check) : null,
              ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('範囲を指定…'),
              onTap: () async {
                final custom = await showDialog<TimeWindow>(
                  context: context,
                  builder: (_) => _CustomRangeDialog(current: current),
                );
                if (context.mounted) Navigator.of(context).pop(custom);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// 「1時間前から2時間前まで」のような範囲の指定。
class _CustomRangeDialog extends StatefulWidget {
  const _CustomRangeDialog({required this.current});

  final TimeWindow current;

  @override
  State<_CustomRangeDialog> createState() => _CustomRangeDialogState();
}

class _CustomRangeDialogState extends State<_CustomRangeDialog> {
  static const List<Duration> _choices = [
    Duration.zero,
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 6),
    Duration(hours: 12),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 15),
    Duration(days: 30),
  ];

  late Duration _from = widget.current.minAge;
  late Duration _to = widget.current.maxAge ?? const Duration(hours: 24);

  String _label(Duration duration) =>
      duration == Duration.zero ? '今' : '${TimeWindow.spanLabel(duration)}前';

  @override
  Widget build(BuildContext context) {
    // 上限が下限より新しいと何も出なくなるため、選べないようにしておく。
    final valid = _to > _from;

    return AlertDialog(
      title: const Text('期間を指定'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DurationRow(
            label: '新しい側',
            value: _from,
            choices: _choices,
            labelOf: _label,
            onChanged: (value) => setState(() => _from = value),
          ),
          _DurationRow(
            label: '古い側',
            value: _to,
            choices: _choices.skip(1).toList(),
            labelOf: _label,
            onChanged: (value) => setState(() => _to = value),
          ),
          const SizedBox(height: 8),
          Text(
            valid
                ? '${_label(_from)}から${_label(_to)}までの情報を表示します'
                : '古い側は新しい側より前の時刻にしてください',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context)
                  .pop(TimeWindow(minAge: _from, maxAge: _to))
              : null,
          child: const Text('この範囲にする'),
        ),
      ],
    );
  }
}

class _DurationRow extends StatelessWidget {
  const _DurationRow({
    required this.label,
    required this.value,
    required this.choices,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final Duration value;
  final List<Duration> choices;
  final String Function(Duration) labelOf;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: DropdownButton<Duration>(
            isExpanded: true,
            value: value,
            items: [
              for (final choice in choices)
                DropdownMenuItem(value: choice, child: Text(labelOf(choice))),
            ],
            onChanged: (selected) {
              if (selected != null) onChanged(selected);
            },
          ),
        ),
      ],
    );
  }
}
