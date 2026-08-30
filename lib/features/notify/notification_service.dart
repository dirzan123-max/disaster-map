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

  /// Windows のトースト通知に使う識別子。
  ///
  /// GUID はアプリごとに固有であればよく、変えると通知の履歴が別物になる。
  static const WindowsInitializationSettings _windowsSettings =
      WindowsInitializationSettings(
    appName: '災害情報マップ',
    appUserModelId: 'com.yjfuj.disaster_map',
    guid: '6f3d9c21-5f0a-4b6e-9a3f-1c8d2b4e7a50',
  );

  Future<void> init() async {
    // Web にはローカル通知の仕組みが無いため何もしない。
    // Web 版は画面内のプレビューと Webhook 連携で代替する。
    if (kIsWeb || _initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: _windowsSettings,
    );
    await _plugin.initialize(settings: settings);

    // チャンネルは Android の仕組み。他の環境では何も返らない。
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_urgentChannel);
    await android?.createNotificationChannel(_normalChannel);
    _initialized = true;
  }

  /// 端末側で通知が許可されているか。
  ///
  /// アプリ内で「通知を受け取る」を ON にしていても、端末の許可が無ければ
  /// 何も鳴らない。設定画面でその状態に気づけるようにするために使う。
  Future<bool> isPermitted() async {
    if (kIsWeb) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android 以外は許可の仕組みが無く、そのまま出せる。
    if (android == null) return true;
    return await android.areNotificationsEnabled() ?? false;
  }

  /// Android 13 以降は通知の許可をユーザーに求める必要がある。
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? false;
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
        windows: const WindowsNotificationDetails(),
      ),
    );
  }
}
