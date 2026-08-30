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
    this.countryCode,
    this.sourceUrl,
    this.isOngoing = false,
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

  /// 座標から判定した国・地域のコード（ISO 3166-1 alpha-2）。
  /// 外洋など、どの国にも寄せられない場合は null。
  final String? countryCode;

  /// 出典の表示名（例: 「気象庁」「USGS」）。画面に必ず表示する。
  final String sourceName;

  /// 出典の詳細ページ URL。詳細画面から開く。
  final String? sourceUrl;

  /// 詳細画面に並べる追加情報（例: 各地の震度、発表中の警報名）。
  final List<String> details;

  /// 「今も続いている状態」を表す情報か。
  ///
  /// 気象警報と噴火警報がこれにあたる。配信元が「今出ているもの」だけを
  /// 配信していて、[occurredAt] は発生時刻ではなく
  /// 「最後に発表・更新された時刻」を指す。
  /// 一覧で「継続中」「◯◯ 更新」と書き分けるために使う。
  ///
  /// 絞り込みからは外さない。外すと期間を変えても件数が変わらず、
  /// 絞り込みが壊れているように見えるため。
  final bool isOngoing;

  bool get hasLocation => latitude != null && longitude != null;

  /// 国の判定結果だけを差し替える。判定は取得後にまとめて行うため、
  /// 各データソースは国を知らないまま [DisasterEvent] を作れる。
  DisasterEvent withCountry(String? code) => DisasterEvent(
        id: id,
        kind: kind,
        severity: severity,
        title: title,
        occurredAt: occurredAt,
        sourceName: sourceName,
        latitude: latitude,
        longitude: longitude,
        subtitle: subtitle,
        magnitude: magnitude,
        depthKm: depthKm,
        areaName: areaName,
        countryCode: code,
        sourceUrl: sourceUrl,
        isOngoing: isOngoing,
        details: details,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is DisasterEvent && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DisasterEvent($id, ${kind.name}, ${severity.name}, $title)';
}
