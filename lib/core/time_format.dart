import 'package:intl/intl.dart';

/// 時刻はすべて UTC で保持し、表示の直前に端末のローカル時刻へ直す。
///
/// 日本の情報は JST、世界の情報は UTC で発表されるため、
/// 内部で UTC に揃えておかないと 9 時間ずれた表示になりやすい。
String formatLocal(DateTime utc) =>
    DateFormat('M/d HH:mm').format(utc.toLocal());

String formatLocalFull(DateTime utc) =>
    DateFormat('yyyy/MM/dd HH:mm').format(utc.toLocal());

/// 「3分前」のような相対表記。最終更新の鮮度を一目で分かるようにする。
String formatElapsed(DateTime utc, {bool english = false}) {
  final elapsed = DateTime.now().toUtc().difference(utc);
  if (elapsed.inMinutes < 1) return english ? 'just now' : 'たった今';
  if (elapsed.inMinutes < 60) {
    return english ? '${elapsed.inMinutes} min ago' : '${elapsed.inMinutes}分前';
  }
  if (elapsed.inHours < 24) {
    return english ? '${elapsed.inHours} h ago' : '${elapsed.inHours}時間前';
  }
  return english ? '${elapsed.inDays} d ago' : '${elapsed.inDays}日前';
}
