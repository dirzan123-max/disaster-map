/// 災害の種別。日本版・世界版のどのデータソースから来たイベントも、
/// 最終的にこのいずれかに分類される。
enum EventKind {
  earthquake,
  tsunami,
  weatherWarning,
  volcano,
  wildfire,
  flood,
  storm,
  other;

  /// 日本語の表示名。
  String get labelJa => switch (this) {
        EventKind.earthquake => '地震',
        EventKind.tsunami => '津波',
        EventKind.weatherWarning => '気象警報',
        EventKind.volcano => '火山',
        EventKind.wildfire => '山火事',
        EventKind.flood => '洪水',
        EventKind.storm => '暴風・台風',
        EventKind.other => 'その他',
      };
}
