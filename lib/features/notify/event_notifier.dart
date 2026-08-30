import '../../domain/disaster_event.dart';
import '../settings/notification_settings.dart';
import 'notification_service.dart';
import 'seen_store.dart';
import 'webhook_sender.dart';

/// 条件に合う未通知のイベントを、通知と業務チャットへ流す。
///
/// 経路は3つある（Android の定期取得、常駐監視、デスクトップの監視）が、
/// 「どれを鳴らすか」「二重に鳴らさないか」の判断はここ1か所に置く。
/// 経路ごとに書くと、条件がずれて「片方だけ鳴る」ことになるため。
class EventNotifier {
  const EventNotifier._();

  /// 通知した件数を返す。
  static Future<int> notify(
    Iterable<DisasterEvent> events,
    NotificationSettings settings,
  ) async {
    final candidates = events.where(settings.matches).toList();
    if (candidates.isEmpty) return 0;

    // 同じ内容で繰り返し鳴らさないよう、未通知のものだけに絞る。
    const seenStore = SeenStore();
    final unseen =
        (await seenStore.filterUnseen(candidates.map((e) => e.id).toList()))
            .toSet();
    if (unseen.isEmpty) return 0;

    const webhook = WebhookSender();
    var sent = 0;
    for (final event in candidates.where((e) => unseen.contains(e.id))) {
      await NotificationService.instance.show(event);
      if (settings.hasWebhook) await webhook.send(event, settings);
      sent++;
    }
    return sent;
  }
}
