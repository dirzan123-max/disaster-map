/// 気象庁が震源座標に使う ISO 6709 形式（例: "+41.3+139.5-10000/"）を
/// 緯度・経度・深さへ分解する。
///
/// 深さはメートルの負値で入っているため、正のキロメートルへ直す。
/// Power BI 版（re/ingest/Fetch-JmaQuake.ps1）と同じ解釈。
class Iso6709Point {
  const Iso6709Point({required this.latitude, required this.longitude, this.depthKm});

  final double latitude;
  final double longitude;

  /// 深さ（km、正の値）。座標のみで深さが無い場合は null。
  final double? depthKm;
}

/// 分解できない場合は null を返す（座標不明の情報は地図に出さない）。
Iso6709Point? parseIso6709(String? source) {
  if (source == null) return null;
  final text = source.trim();
  if (text.isEmpty) return null;

  // 符号付きの数値を順に拾う。1つ目=緯度、2つ目=経度、3つ目=深さ(m)。
  final matches = RegExp(r'[+-]\d+(?:\.\d+)?').allMatches(text).toList();
  if (matches.length < 2) return null;

  final latitude = double.tryParse(matches[0].group(0)!);
  final longitude = double.tryParse(matches[1].group(0)!);
  if (latitude == null || longitude == null) return null;
  if (latitude.abs() > 90 || longitude.abs() > 180) return null;

  double? depthKm;
  if (matches.length >= 3) {
    final depthMeters = double.tryParse(matches[2].group(0)!);
    if (depthMeters != null) depthKm = depthMeters.abs() / 1000;
  }

  return Iso6709Point(latitude: latitude, longitude: longitude, depthKm: depthKm);
}
