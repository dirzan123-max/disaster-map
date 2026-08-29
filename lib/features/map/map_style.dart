import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/region.dart';

/// 地図タイルの設定。地域ごとに出典と初期表示範囲が変わる。
///
/// どちらも無料で使えるタイルだが、出典表示が利用条件に含まれるため
/// [attribution] を画面に必ず出す。差し替えたくなったらここだけ直せばよい。
class MapStyle {
  const MapStyle({
    required this.urlTemplate,
    required this.attribution,
    required this.center,
    required this.zoom,
    required this.maxZoom,
  });

  final String urlTemplate;
  final String attribution;
  final LatLng center;
  final double zoom;
  final double maxZoom;

  static const MapStyle japan = MapStyle(
    // 地理院タイル（淡色）。出典表示を条件に無償で利用できる。
    urlTemplate: 'https://cyberjapandata.gsi.go.jp/xyz/pale/{z}/{x}/{y}.png',
    attribution: '地理院タイル（国土地理院）',
    center: LatLng(37.5, 137.0),
    zoom: 4.6,
    maxZoom: 17,
  );

  static const MapStyle world = MapStyle(
    // OpenStreetMap の標準タイル。鍵なしで使えるが、大量取得は禁じられている
    // （CARTO の無償タイルは API キーが必要になり、透かしが入るため不採用）。
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    center: LatLng(20.0, 10.0),
    zoom: 1.8,
    maxZoom: 18,
  );

  static MapStyle of(Region region) =>
      region == Region.japan ? japan : world;

  /// タイル配信元に素性を伝えるための識別子。
  /// 地理院タイル・CARTO とも、大量取得を避ける前提での利用を求めている。
  static const String userAgentPackageName = 'com.yjfuj.disaster_map';

  TileLayer toTileLayer() => TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: userAgentPackageName,
        maxNativeZoom: maxZoom.toInt(),
        // 端末の回線が細い災害時を想定し、取得済みタイルは積極的に使い回す。
        keepBuffer: 3,
      );
}
