/// 表示対象の地域。日本版と世界版でデータソース・地図タイル・
/// 初期表示範囲・表示言語がすべて切り替わる。
enum Region {
  japan,
  world;

  String get labelJa => this == Region.japan ? '日本' : '世界';
  String get labelEn => this == Region.japan ? 'Japan' : 'World';

  /// 世界版は英語表記にする（データソース自体が英語のため）。
  bool get useEnglish => this == Region.world;
}
