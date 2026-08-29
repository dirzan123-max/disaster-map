import '../../domain/disaster_event.dart';

/// 1つの外部 API を担当し、その応答を [DisasterEvent] のリストへ正規化する。
///
/// 実装クラスは「取ってきて変換する」ことだけを行い、
/// 並列実行・失敗時の扱い・キャッシュは DisasterRepository の責任とする。
abstract class DisasterSource {
  /// 画面に表示する出典名（例: 「気象庁」「USGS」）。
  String get sourceName;

  /// 取得して正規化する。失敗時は例外を投げてよい
  /// （Repository が握りつぶし、他のソースの結果は活かす）。
  Future<List<DisasterEvent>> fetch();
}

/// 応答の文字列を DisasterEvent へ変換する部分を切り出した Source。
///
/// [parse] はネットワークに触らないため、保存済みのフィクスチャに対して
/// ユニットテストできる。API 側の仕様変更はここのテストで検知する。
abstract class ParsingSource extends DisasterSource {
  List<DisasterEvent> parse(String body);
}
