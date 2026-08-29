import 'event_kind.dart';
import 'severity.dart';

/// 全データソースを正規化した統一イベントモデル。
///
/// 地図・リスト・通知・Webhook は、元の API の形式を一切知らずに
/// このモデルだけを扱う。新しいデータソースを足すときは、
/// そのソース用の Source クラスがこの形へ変換する責任を持つ。
class DisasterEvent {
  const DisasterEvent({
    required this.id,
    required this.kind,
    required this.severity,
    required this.title,
    required this.occurredAt,
    required this.sourceName,
    this.latitude,
    this.longitude,
    this.subtitle,
    this.magnitude,
    this.depthKm,
    this.areaName,
    this.sourceUrl,
    this.details = const <String>[],
  });

  /// ソース名を含む一意な ID。通知済み判定のキーに使うため、
  /// 同じイベントを再取得しても同じ値になる必要がある。
  final String id;
  final EventKind kind;
  final Severity severity;

  /// 一覧・通知の見出し（例: 「青森県西方沖 M3.7 最大震度1」）。
  final String title;

  /// 補足行（例: 「深さ10km / 津波の心配なし」）。
  final String? subtitle;

  /// 座標。津波予報区のように面で発表され代表点を持たない情報は null になり、
  /// その場合は地図には出さずリストにだけ表示する。
  final double? latitude;
  final double? longitude;

  /// 発生時刻。全ソースで UTC に揃えて保持し、表示時にローカルへ変換する。
  final DateTime occurredAt;

  final double? magnitude;
  final double? depthKm;

  /// 地域名（震源地名・区域名・国名など）。
  final String? areaName;

  /// 出典の表示名（例: 「気象庁」「USGS」）。画面に必ず表示する。
  final String sourceName;

  /// 出典の詳細ページ URL。詳細画面から開く。
  final String? sourceUrl;

  /// 詳細画面に並べる追加情報（例: 各地の震度、発表中の警報名）。
  final List<String> details;

  bool get hasLocation => latitude != null && longitude != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DisasterEvent && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DisasterEvent($id, ${kind.name}, ${severity.name}, $title)';
}
