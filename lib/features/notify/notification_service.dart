import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/disaster_event.dart';
import '../../domain/severity.dart';

/// 端末のローカル通知。
///
/// サーバーを持たない構成のため、プッシュ通知（FCM）ではなく
/// 「端末が定期的に取りに行き、条件に合えば自分で鳴らす」方式にしている。
/// これなら運用費がかからず、個人開発でも継続できる。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 深刻度の高い情報を、通常の通知に埋もれさせないためのチャンネル分け。
  static const AndroidNotificationChannel _urgentChannel =
      AndroidNotificationChannel(
    'disaster_urgent',
    '重大な災害情報',
    description: '警戒・重大レベルの災害情報を知らせます。',
    importance: Importance.max,
  );

  static const AndroidNotificationChannel _normalChannel =
      AndroidNotificationChannel(
    'disaster_normal',
    '災害情報',
    description: '設定した条件に合う災害情報を知らせます。',
    importance: Importance.defaultImportance,
  );

  Future<void> init() async {
    // Web にはローカル通知の仕組みが無いため何もしない。
    // Web 版は画面内のプレビューと Webhook 連携で代替する。
    if (kIsWeb || _initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings: settings);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_urgentChannel);
    await android?.createNotificationChannel(_normalChannel);
    _initialized = true;
  }

  /// Android 13 以降は通知の許可をユーザーに求める必要がある。
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  Future<void> show(DisasterEvent event) async {
    if (kIsWeb) return;
    await init();

    final urgent = event.severity.level >= Severity.severe.level;
    final channel = urgent ? _urgentChannel : _normalChannel;

    await _plugin.show(
      // 同じイベントで通知が重複しないよう、ID から一意な整数を作る。
      id: event.id.hashCode & 0x7fffffff,
      title: '【${event.severity.labelJa}】${event.title}',
      body: [
        if (event.subtitle != null && event.subtitle!.isNotEmpty) event.subtitle!,
        event.sourceName,
      ].join(' ・ '),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: urgent ? Importance.max : Importance.defaultImportance,
          priority: urgent ? Priority.high : Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(event.details.join('\n')),
        ),
      ),
    );
  }

  /// 設定画面から経路を確かめるためのテスト通知。
  /// 定期取得の15分を待たずに、通知が出る状態かを確認できる。
  Future<void> showTest() async {
    if (kIsWeb) return;
    await init();
    await _plugin.show(
      id: 0,
      title: '【テスト】災害情報マップ',
      body: '通知はこの形で届きます。実際の通知は設定した条件を満たしたときだけ鳴ります。',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _normalChannel.id,
          _normalChannel.name,
          channelDescription: _normalChannel.description,
        ),
      ),
    );
  }
}
