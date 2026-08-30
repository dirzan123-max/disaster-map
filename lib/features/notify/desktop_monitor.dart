import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../data/sources/p2p_quake_source.dart';
import '../app_state.dart';
import 'event_notifier.dart';
import 'realtime_monitor.dart';

/// パソコンで開いている間の監視。
///
/// Android は端末に任せて動く仕組み（WorkManager・常駐サービス）があるが、
/// パソコンにはそれが無い。代わりに**アプリが開いている限り動き続ける**ので、
/// アプリ自身が定期的に取りに行き、条件に合えば通知する。
///
/// 対策本部の PC で一日中開いておく、という使い方を想定している。
/// 常駐サービスの申請も、通知バーの居座りも要らないぶん、
/// Android よりむしろ素直に動く。
class DesktopMonitor {
  DesktopMonitor(this.state);

  final AppState state;

  /// 取りに行く間隔。
  ///
  /// Android の15分と違って端末側の制限が無いので短くできるが、
  /// 配信元に負荷をかけないよう5分にしている。
  /// これより速く知りたいときはリアルタイム監視を使う。
  static const Duration interval = Duration(minutes: 5);

  /// この仕組みが要る環境か。
  ///
  /// Android は端末の仕組みに任せる。Web は通知そのものが出せない。
  static bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Timer? _timer;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _busy = false;

  void start() {
    if (!isSupported || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_check()));
    unawaited(_applyRealtime());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _disconnect();
  }

  /// 設定が変わったときに、リアルタイム監視の入切を合わせる。
  Future<void> settingsChanged() => _applyRealtime();

  Future<void> _check() async {
    if (_busy) return;
    _busy = true;
    try {
      await state.refresh();
      final snapshot = state.snapshot;
      if (snapshot != null) {
        await EventNotifier.notify(snapshot.events, state.settings);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _applyRealtime() async {
    final wanted = state.settings.enabled && state.settings.realtime;
    if (wanted && _channel == null) {
      await _connect();
    } else if (!wanted && _channel != null) {
      await _disconnect();
    }
  }

  /// 地震の発表を待たずに受け取る。
  /// パソコンでは常駐サービスが要らないので、そのままつなぐだけでよい。
  Future<void> _connect() async {
    try {
      final channel = WebSocketChannel.connect(RealtimeMonitor.endpoint);
      await channel.ready;
      _channel = channel;
      _subscription = channel.stream.listen(
        (message) => unawaited(_handleMessage('$message')),
        onError: (Object _) => unawaited(_reconnectLater()),
        onDone: () => unawaited(_reconnectLater()),
        cancelOnError: true,
      );
    } catch (_) {
      await _reconnectLater();
    }
  }

  /// 切れたら少し待ってつなぎ直す。
  /// 切れたまま「監視中」と見せるのが一番まずい。
  Future<void> _reconnectLater() async {
    await _disconnect();
    Timer(const Duration(seconds: 30), () {
      if (_timer != null) unawaited(_applyRealtime());
    });
  }

  Future<void> _disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> _handleMessage(String message) async {
    try {
      final events = P2pQuakeSource().parseMessage(message);
      if (events.isEmpty) return;
      await EventNotifier.notify(events, state.settings);
      // 届いた内容を画面にも反映する。
      await state.refresh();
    } catch (_) {
      // 想定外の形が流れてきても、監視そのものは止めない。
    }
  }
}
