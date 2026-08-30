import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/sources/p2p_quake_source.dart';
import '../../domain/disaster_event.dart';
import '../settings/notification_settings.dart';
import 'event_notifier.dart';

/// 地震の発表を、待たずに受け取る常駐監視。
///
/// 定期取得（[BackgroundWorker]）は Android の制限で15分ごとが上限で、
/// 「揺れた直後に規模を知る」には遅い。
/// P2P地震情報が WebSocket を公開しているので、つなぎっぱなしにして
/// 発表が流れてきた瞬間に通知する。サーバーを持たずに秒単位にできる。
///
/// 代償として、Android では常駐サービス（通知バーに居座る）が要る。
/// 電池も食うため、既定では止めてあり、設定で明示的に入れてもらう。
///
/// 受け取れるのは地震・津波だけ。気象警報や海外の情報は定期取得のまま。
/// なお緊急地震速報（揺れる前に鳴るもの）はこの経路では扱えない。
/// あれは携帯網から端末の OS 機能へ直接届くもので、アプリからは触れない。
class RealtimeMonitor {
  const RealtimeMonitor._();

  /// P2P地震情報の配信。接続に鍵は要らない。
  /// https://www.p2pquake.net/develop/json_api_v2/
  static final Uri endpoint = Uri.parse('wss://api.p2pquake.net/v2/ws');

  static const String channelId = 'disaster_realtime';

  /// 常駐サービスが動いているか。
  static Future<bool> get isRunning async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    return FlutterForegroundTask.isRunningService;
  }

  /// アプリ起動時に一度だけ呼ぶ。常駐用の通知の見た目を決める。
  static void init() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: 'リアルタイム監視',
        channelDescription: '地震の発表を待たずに受け取るため、常駐していることを示します。',
        // 監視していること自体は静かに出す。鳴るのは災害の通知だけ。
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // 接続が切れていないかを見るだけなので、間隔は長くてよい。
        eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (await FlutterForegroundTask.isRunningService) return true;

    final result = await FlutterForegroundTask.startService(
      // 継続的な災害監視のための常駐。dataSync は Android 15 で
      // 24時間あたり6時間までに制限されるため、specialUse を使う。
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: 'リアルタイム監視中',
      notificationText: '地震の発表を待たずに受け取ります',
      callback: realtimeCallback,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  /// 設定に合わせて、常駐を開始／停止する。開始できたかを返す。
  static Future<bool> applySetting(NotificationSettings settings) async {
    if (settings.enabled && settings.realtime) return start();
    await stop();
    return false;
  }
}

/// 常駐サービスの入口。トップレベル関数である必要がある。
@pragma('vm:entry-point')
void realtimeCallback() {
  FlutterForegroundTask.setTaskHandler(RealtimeTaskHandler());
}

/// 常駐して WebSocket を見張り、届いた発表を通知する。
class RealtimeTaskHandler extends TaskHandler {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connecting = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _connect();

  /// 定期的に呼ばれる。切れていたらつなぎ直す。
  ///
  /// 圏外や省電力で接続はよく切れる。切れたまま「監視中」と出し続けるのが
  /// 一番まずいので、ここで必ず拾い直す。
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_channel == null && !_connecting) unawaited(_connect());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) => _disconnect();

  Future<void> _connect() async {
    if (_connecting) return;
    _connecting = true;
    try {
      final channel = WebSocketChannel.connect(RealtimeMonitor.endpoint);
      await channel.ready;
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) => unawaited(handleMessage('$message')),
        onError: (Object _) => unawaited(_disconnect()),
        onDone: () => unawaited(_disconnect()),
        cancelOnError: true,
      );
    } catch (_) {
      // つながらなくても常駐は続ける。次の onRepeatEvent でやり直す。
      await _disconnect();
    } finally {
      _connecting = false;
    }
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// 届いた1件を、定期取得と同じ条件で判定して通知する。
  ///
  /// 判定を [NotificationSettings] に任せているので、
  /// 「画面に見えている条件」と「実際に飛ぶ通知」がここでも一致する。
  @visibleForTesting
  Future<void> handleMessage(String message) async {
    final List<DisasterEvent> events;
    try {
      events = P2pQuakeSource().parseMessage(message);
    } catch (_) {
      // 想定外の形が流れてきても、監視そのものは止めない。
      return;
    }
    if (events.isEmpty) return;

    // 判定も通知済みの記録も定期取得と共通。二重に鳴らさない。
    await EventNotifier.notify(events, await NotificationSettings.load());
  }
}
