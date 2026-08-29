import 'package:shared_preferences/shared_preferences.dart';

/// 通知済みイベントの記録。
///
/// 定期取得のたびに同じ地震で通知が鳴るのを防ぐ。
/// ID は DisasterEvent.id（発表内容が変われば変わる）を使うので、
/// 続報や警報の更新はきちんと新しい通知として届く。
class SeenStore {
  const SeenStore();

  static const String _key = 'notified_event_ids';

  /// 保持する上限。無限に増やすと保存領域を圧迫するため、古いものから捨てる。
  static const int _maxEntries = 300;

  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_key) ?? const <String>[]).toSet();
  }

  /// 未通知のものだけを返し、同時に通知済みとして記録する。
  Future<List<String>> filterUnseen(List<String> ids) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(_key) ?? const <String>[];
    final seen = stored.toSet();

    final unseen = ids.where((id) => !seen.contains(id)).toList();
    if (unseen.isEmpty) return unseen;

    // 新しいものを末尾に足し、上限を超えた分は先頭（古い方）から捨てる。
    final updated = [...stored, ...unseen];
    final trimmed = updated.length > _maxEntries
        ? updated.sublist(updated.length - _maxEntries)
        : updated;
    await preferences.setStringList(_key, trimmed);
    return unseen;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
