import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 世界地図をどこを中心に見せるか。
///
/// 地図は経度の一次元でつながっているので、「中心をどこに置くか」は
/// 「どこで切るか」と同じ。日本中心なら継ぎ目は大西洋、
/// イギリス中心なら継ぎ目は太平洋（日付変更線）に来る。
enum WorldCenter {
  japan(140, '日本が中心', '継ぎ目は大西洋。太平洋を丸ごと見られます'),
  greenwich(0, 'イギリスが中心', '継ぎ目は太平洋。世界地図としてよくある形です');

  const WorldCenter(this.longitude, this.label, this.description);

  /// 画面の真ん中に来る経度。
  final double longitude;
  final String label;
  final String description;
}

/// 地図タイルの設定。
///
/// 地図は1つなので、タイルも1種類に絞っている。
/// 地理院タイル（淡色）は国内だけ美しいが国外が真っ白になるため、
/// 世界まで1枚で見せるこの構成では使えない。
/// 無料で使えるが、出典表示が利用条件に含まれるため必ず画面に出す。
class MapStyle {
  const MapStyle._();

  /// OpenStreetMap の標準タイル。鍵なしで使え、日本語の地名も入っている
  /// （CARTO の無償タイルは API キーが必要になり、透かしが入るため不採用）。
  static const String urlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const String attribution = '© OpenStreetMap contributors';

  static const double maxZoom = 18;

  /// 縮小の下限。世界1周が画面幅にちょうど収まるところで止める。
  ///
  /// タイルは1枚 256px で、ズーム z のとき世界全体が 256 * 2^z px になる。
  static double fitZoom(Size size) => math.log(size.width / 256) / math.ln2;

  /// 全世界が対象の種別を開いたときに映す位置。
  static LatLng centerOf(WorldCenter world) => LatLng(20, world.longitude);

  /// 地図の中心を動かせる範囲（南北）。東西は [clampLongitude] で別に縛る。
  static LatLngBounds get cameraBounds => LatLngBounds(
        const LatLng(-85, -180),
        const LatLng(85, 180),
      );

  /// 画面が「世界1周ぶんの窓」から出ないように、中心の経度を戻す。
  ///
  /// 地図は東西に繰り返し描かれるので、そのままだと同じ世界地図が
  /// 何枚も出てくる。かといって繰り返しそのものを切ると、
  /// 地図の実体が経度 -180〜180 の1枚に固定され、
  /// **日本を真ん中に置いた世界地図が作れなくなる**（右側が空白になる）。
  ///
  /// そこで繰り返しは有効なまま、[world] を中心とした1周分だけを
  /// 動かせる窓とし、その外へ出たら戻す。継ぎ目は窓の反対側に来る。
  ///
  /// 戻す必要がなければ null を返す。
  static LatLng? clampLongitude(
    MapCamera camera,
    double screenWidth,
    WorldCenter world,
  ) {
    final worldWidth = camera.crs.scale(camera.zoom);
    // 画面の半分が、経度に直して何度ぶんか。
    final halfDegrees = screenWidth / worldWidth * 360 / 2;
    // 中心からの「ずれ」を -180〜180 で見る（継ぎ目をまたいでも扱えるように）。
    final shifted = shiftLongitude(camera.center.longitude, world);

    final limit = math.max(0.0, 180 - halfDegrees);
    final clamped = shifted.clamp(-limit, limit);
    if ((clamped - shifted).abs() < 0.0001) return null;
    return LatLng(camera.center.latitude, _unshift(clamped, world.longitude));
  }

  /// [world] の中心を 0 とみなしたときの経度（-180〜180）。
  static double shiftLongitude(double longitude, WorldCenter world) =>
      _shift(longitude, world.longitude);

  static double _shift(double longitude, double origin) =>
      ((longitude - origin + 540) % 360) - 180;

  static double _unshift(double shifted, double origin) =>
      ((shifted + origin + 540) % 360) - 180;

  /// タイル配信元に素性を伝えるための識別子。
  /// 大量取得を避ける前提での利用を求められている。
  static const String userAgentPackageName = 'com.yjfuj.disaster_map';

  static TileLayer toTileLayer() => TileLayer(
        urlTemplate: urlTemplate,
        userAgentPackageName: userAgentPackageName,
        maxNativeZoom: maxZoom.toInt(),
        // 端末の回線が細い災害時を想定し、取得済みタイルは積極的に使い回す。
        keepBuffer: 3,
      );
}
