import 'package:flutter/material.dart';

import 'data/area_points.dart';
import 'data/disaster_repository.dart';
import 'features/app_state.dart';
import 'features/home_page.dart';
import 'features/notify/background_worker.dart';
import 'features/notify/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(DisasterMapApp(state: state));
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

class DisasterMapApp extends StatelessWidget {
  const DisasterMapApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '災害情報マップ',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: HomePage(state: state),
    );
  }
}
