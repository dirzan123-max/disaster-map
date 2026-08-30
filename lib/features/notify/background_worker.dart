import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../data/area_points.dart';
import '../../data/disaster_repository.dart';
import '../settings/notification_settings.dart';
import 'event_notifier.dart';

/// バックグラウンドでの定期チェック（Android のみ）。
///
/// サーバーを立てない代わりに、端末が 15 分ごとに自分で取りに行く。
/// 15 分は Android WorkManager が許す最短間隔で、これより短くはできない。
/// 即時性が必要な用途では、同梱の GitHub Actions ワークフロー側で
/// 短い間隔の監視を回し、Webhook で通知する構成を想定している。
class BackgroundWorker {
  const BackgroundWorker._();

  static const String taskName = 'disaster_map_periodic_check';
  static const Duration interval = Duration(minutes: 15);

  /// アプリ起動時に呼ぶ。Web では何もしない。
  static Future<void> register() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: interval,
      constraints: Constraints(networkType: NetworkType.connected),
      // 設定を変えて登録し直しても、既存の予約を置き換えるだけにする。
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().cancelByUniqueName(taskName);
  }

  /// 定期実行の本体。UI とは別のはたらきで動くため、
  /// 画面の状態には触らず、保存された設定だけを見る。
  static Future<bool> runCheck() async {
    final settings = await NotificationSettings.load();
    if (!settings.enabled || settings.rules.notifiesNothing) return true;

    final assets = await AreaAssets.load();
    final repository = DisasterRepository(assets: assets);
    final snapshot = await repository.fetch();

    await EventNotifier.notify(snapshot.events, settings);
    return true;
  }
}

/// WorkManager から呼ばれる入口。トップレベル関数である必要がある。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != BackgroundWorker.taskName) return true;
    try {
      return await BackgroundWorker.runCheck();
    } catch (_) {
      // 取得や通知に失敗しても、次の実行機会を潰さないよう成功扱いで返す。
      return true;
    }
  });
}
