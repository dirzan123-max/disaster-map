import 'package:flutter/material.dart';

import 'tutorial_page.dart';

/// 初めて開いたときの案内。
///
/// 3枚だけ・1枚1文にしている。最初に長い説明を読ませても誰も読まないため、
/// ここでは「何ができるか」だけを見せ、細かい話（データの範囲や出典）は
/// 設定画面の「使い方とデータの範囲」に置いている。
/// いつでもスキップできる。
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key, required this.onFinish});

  /// 見終わった（または飛ばした）とき。地図へ進む。
  final VoidCallback onFinish;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = [
    _Slide(
      icon: Icons.public,
      title: '1つの地図で、日本も世界も',
      body: '日本国内は気象庁、国外は USGS と NASA の情報を\n'
          '自動で使い分けます。切り替えの操作は要りません。',
    ),
    _Slide(
      icon: Icons.tune,
      title: '見たいものだけに絞れます',
      body: '災害の種類・深刻度・さかのぼる期間で絞り込めます。\n'
          '選んだ条件は覚えているので、次に開いたときも同じ状態です。',
    ),
    _Slide(
      icon: Icons.notifications_active_outlined,
      title: '危ないときは通知で気づけます',
      body: '15分ごとに自動で確認し、条件に合えばお知らせします。\n'
          '「地震は警戒以上、津波は注意から」のように、\n'
          '種類ごとに強さを決められます。',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onFinish,
                child: const Text('スキップ'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, index) => _slides[index],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < _slides.length; index++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? '地図をひらく' : 'つぎへ'),
                ),
              ),
            ),
            // 細かい説明を読みたい人だけが辿れればよいので、小さく置く。
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const TutorialPage()),
              ),
              child: Text(
                'くわしい使い方とデータの範囲',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
