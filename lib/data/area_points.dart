import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 区域コード・火山コードに対応する代表点。
///
/// 気象庁の警報は「区域」単位、噴火警報は「火山」単位で発表され、
/// 応答そのものには座標が含まれない。地図に出すために、
/// tool/build_assets.py が公式データから生成した座標表をアプリへ同梱している。
class AreaPoint {
  const AreaPoint({
    required this.code,
    required this.name,
    required this.enName,
    required this.latitude,
    required this.longitude,
  });

  final String code;
  final String name;
  final String enName;
  final double latitude;
  final double longitude;

  /// 英語名が空のレコードがあるため、無ければ日本語名で代替する。
  String label({required bool english}) =>
      english && enName.isNotEmpty ? enName : name;
}

/// 座標表（コード -> 代表点）。
typedef AreaPoints = Map<String, AreaPoint>;

AreaPoints parseAreaPoints(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) return const {};

  final points = <String, AreaPoint>{};
  decoded.forEach((code, value) {
    if (value is! Map<String, dynamic>) return;
    final latitude = (value['lat'] as num?)?.toDouble();
    final longitude = (value['lon'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return;
    points[code] = AreaPoint(
      code: code,
      name: (value['name'] as String?) ?? '',
      enName: (value['enName'] as String?) ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  });
  return points;
}

Map<String, String> parseAreaNames(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) return const {};
  return decoded.map((code, name) => MapEntry(code, name.toString()));
}

/// 同梱アセットの読み込み。アプリ起動時に一度だけ呼ぶ。
class AreaAssets {
  const AreaAssets({
    required this.class10Points,
    required this.volcanoPoints,
    required this.areaNames,
  });

  /// 気象警報の一次細分区域（143件）。
  final AreaPoints class10Points;

  /// 常時観測火山（117件）。
  final AreaPoints volcanoPoints;

  /// 区域コード -> 名称（市町村を含む全階層）。
  final Map<String, String> areaNames;

  static const AreaAssets empty = AreaAssets(
    class10Points: {},
    volcanoPoints: {},
    areaNames: {},
  );

  static Future<AreaAssets> load() async {
    final results = await Future.wait([
      rootBundle.loadString('assets/jma_class10_points.json'),
      rootBundle.loadString('assets/jma_volcano_points.json'),
      rootBundle.loadString('assets/jma_area_names.json'),
    ]);
    return AreaAssets(
      class10Points: parseAreaPoints(results[0]),
      volcanoPoints: parseAreaPoints(results[1]),
      areaNames: parseAreaNames(results[2]),
    );
  }
}
