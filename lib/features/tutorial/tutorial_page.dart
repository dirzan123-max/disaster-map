import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/coverage.dart';
import '../../domain/event_kind.dart';
import '../event_style.dart';

/// 使い方と、情報がどこまで取れているかの詳しい説明。
///
/// 初回に見せるのは [WelcomePage] の3枚だけにして、この画面は
/// 「もっと知りたい人が開くもの」に留めている。
/// 最初にこの量を読ませても誰も読まないため。
///
/// 「このアプリについて」（出典・免責）は、普段は見ないものなので
/// この画面のいちばん下に畳んで置いている。
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  /// 初回起動かどうかの記録に使うキー。
  static const String _seenKey = 'tutorial_seen';

  static Future<bool> hasSeen() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_seenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_seenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('使い方とデータの範囲')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: const [
          _Step(
            icon: Icons.public,
            title: '1つの地図で、日本も世界も見る',
            body: '日本国内は気象庁（震度つきの地震・津波・気象警報・噴火警報）、'
                '国外は USGS と NASA（地震・火山・台風・山火事）の情報を'
                '自動で使い分けています。'
                '同じ地震が両方から来たときは、詳しい気象庁の方を出します。',
          ),
          _Step(
            icon: Icons.category_outlined,
            title: '見る災害は1つずつ選ぶ',
            body: '地図の上のチップで、地震・気象警報などを1つ選びます。'
                'その下で「深刻度」「期間」を絞り込めます。'
                '選んだ条件は次に開いたときも残ります。',
          ),
          _Step(
            icon: Icons.swipe_up,
            title: '下から一覧を引き出す',
            body: '画面下の横棒を上に引くと一覧が開きます。棒を叩いても開閉します。'
                '地図に出せない情報（津波予報区など）も、一覧には必ず出ます。',
          ),
          _Step(
            icon: Icons.notifications_outlined,
            title: '通知は種類ごとに強さを決める',
            body: '15分ごとに自動で確認し、条件に合えば通知します。'
                '「地震は警戒以上、津波は注意から」のように、'
                '種類ごとに深刻度を選べます。',
          ),
          _CoverageSection(),
          _Disclaimer(),
          _About(),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 種別ごとに、どこまで情報が取れているか。
///
/// 「山火事は米国の情報しか無い」のように、
/// 取れていない範囲を知らずに使うと「起きていない」と誤解するため、
/// 使い方と同じ場所に必ず出す。
class _CoverageSection extends StatelessWidget {
  const _CoverageSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Text('どこまで取れているか', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '種類によって、情報源のある範囲が違います。'
          '選んだ種類の情報源が無い範囲は、地図でグレーに塗ります。'
          '「日本にしか出ていない」のではなく「日本しか見ていない」ことが'
          '分かるようにするためです。',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final kind in EventKind.values)
          if (!DataCoverage.of(kind).hasNoSource) _CoverageRow(kind: kind),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'さかのぼれる長さも種類ごとに違います。'
            '地図の「期間」で、選べる範囲としてそのまま出しています。',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.kind});

  final EventKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverage = DataCoverage.of(kind);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(EventStyle.iconOf(kind), size: 16),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(kind.labelJa, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              coverage.caution == null
                  ? coverage.areaLabel
                  : '${coverage.areaLabel}（${coverage.caution}）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: coverage.global
                    ? null
                    : theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'このアプリは状況把握を助ける補助的なものです。'
              '避難などの判断は、必ず自治体や気象庁の公式発表を優先してください。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 出典と、アプリについて。普段は見ないので畳んでおく。
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('このアプリについて', style: theme.textTheme.bodySmall),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '気象庁・USGS・NASA が公開している情報を取得し、地図に重ねて表示します。\n'
              '世界版の情報は英語で配信されているため、方角・単位・国名などを'
              'アプリ内で和訳しています。地名は原文のまま残し、'
              '詳細画面に原文を併記しています。\n\n'
              '出典\n'
              '・気象庁（地震・津波・気象警報・噴火警報）\n'
              '・P2P地震情報（気象庁発表の配信）\n'
              '・USGS Earthquake Hazards Program\n'
              '・NASA EONET\n'
              '・地理院タイル（国土地理院）\n'
              '・Natural Earth（国境データ）\n'
              '・© OpenStreetMap contributors',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
