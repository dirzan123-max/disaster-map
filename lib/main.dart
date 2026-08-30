import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/area_points.dart';
import 'data/disaster_repository.dart';
import 'features/app_state.dart';
import 'features/home_page.dart';
import 'features/settings/notification_settings.dart';
import 'features/notify/background_worker.dart';
import 'features/notify/desktop_monitor.dart';
import 'features/notify/notification_service.dart';
import 'features/notify/realtime_monitor.dart';
import 'features/tutorial/tutorial_page.dart';
import 'features/tutorial/welcome_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 縦画面に固定する。マニフェストにも書いているが、Android 16 は
  // 大きな画面で screenOrientation を無視することがあるため両方で押さえる。
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 区域・火山の代表点はアプリに同梱している。起動時に一度だけ読む。
  final assets = await AreaAssets.load();
  final state = AppState(repository: DisasterRepository(assets: assets));

  // 通知の準備は画面表示を待たせないよう、待たずに進める。
  // Web ではいずれも何もしない実装になっている。
  //
  // 通知の許可は起動時に一度だけ求める。設定画面まで来ないと通知が来ない、
  // という状態を避けるため（Android 13 以降は許可が無いと一切鳴らない）。
  unawaited(NotificationService.instance.requestPermission());
  unawaited(BackgroundWorker.register());

  // 常駐監視は、前回入れたままなら起動時に復帰させる。
  RealtimeMonitor.init();
  unawaited(
    NotificationSettings.load().then(RealtimeMonitor.applySetting),
  );

  // 初めて開いたときだけ、短い案内を先に見せる。
  final seenTutorial = await TutorialPage.hasSeen();

  // パソコンには端末側の定期実行が無いので、アプリ自身が見張る。
  final desktop = DesktopMonitor(state)..start();

  runApp(
    DisasterMapApp(
      state: state,
      desktop: desktop,
      showTutorial: !seenTutorial,
    ),
  );
  await state.init();
}

/// 例外を握りつぶさずに投げ捨てる意図を明示するための小さなヘルパー。
void unawaited(Future<void> future) {
  future.catchError((Object error) {
    debugPrint('background init failed: $error');
  });
}

/// 日本語フォントを明示して、Android と Web で同じ見た目にする。
/// Web は同梱しないと初回表示が豆腐になり、文字幅の計算もずれる。
ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00695C),
        brightness: brightness,
      ),
      useMaterial3: true,
      fontFamily: 'NotoSansJP',
    );

class DisasterMapApp extends StatefulWidget {
  const DisasterMapApp({
    super.key,
    required this.state,
    required this.desktop,
    this.showTutorial = false,
  });

  final AppState state;

  /// パソコンで開いている間の監視。Android・Web では何もしない。
  final DesktopMonitor desktop;

  /// 初回起動なら、地図の前に使い方を出す。
  final bool showTutorial;

  @override
  State<DisasterMapApp> createState() => _DisasterMapAppState();
}

class _DisasterMapAppState extends State<DisasterMapApp> {
  late bool _showTutorial = widget.showTutorial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '災害情報マップ',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: _showTutorial
          ? WelcomePage(
              onFinish: () async {
                await TutorialPage.markSeen();
                if (mounted) setState(() => _showTutorial = false);
              },
            )
          : HomePage(state: widget.state, desktop: widget.desktop),
    );
  }
}
