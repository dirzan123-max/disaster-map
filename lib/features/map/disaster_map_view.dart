import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/coverage.dart';
import '../../domain/disaster_event.dart';
import '../app_state.dart';
import '../event_style.dart';
import 'map_style.dart';

/// 災害イベントを地図に描く。
///
/// 座標を持たないイベント（津波予報区など）はここには出ない。
/// リスト側で必ず拾えるようにしてあるため、情報自体は失われない。
class DisasterMapView extends StatefulWidget {
  const DisasterMapView({super.key, required this.state});

  final AppState state;

  @override
  State<DisasterMapView> createState() => _DisasterMapViewState();
}

class _DisasterMapViewState extends State<DisasterMapView> {
  final MapController _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 画面の端が世界の外へ出たら、中心を戻す。
  ///
  /// 中心だけを縛る `containCenter` では、一番縮小したときに
  /// 世界1枚ぶん横へ流せてしまい「2枚分の空間がある」ように見える。
  void _keepInsideWorld(MapCamera camera, Size size) {
    final corrected = MapStyle.clampLongitude(
      camera,
      size.width,
      widget.state.worldCenter,
    );
    if (corrected == null) return;
    // 描画の途中で地図を動かせないため、フレーム確定後に戻す。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.move(corrected, camera.zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 縮小の下限は画面の大きさで変わるため、実際の描画領域から決める。
    return LayoutBuilder(
      builder: (context, constraints) => _buildMap(context, constraints.biggest),
    );
  }

  Widget _buildMap(BuildContext context, Size size) {
    final minZoom = MapStyle.fitZoom(size);
    final events =
        widget.state.visibleEvents.where((event) => event.hasLocation).toList();
    final kind = widget.state.selectedKind;
    final coverage = kind == null ? null : DataCoverage.of(kind);

    // 開いたときに映す範囲を、種別に合わせて決める。
    // 情報源が限られた範囲にしかない種別（山火事＝米国、気象警報＝日本）は
    // その範囲を映す。「山火事」を選んで日本を見ていても、そこには何も無い。
    final limited = coverage != null && coverage.boxes.isNotEmpty;
    final fit = limited
        ? CameraFit.bounds(
            bounds: _boundsOf(coverage.boxes),
            padding: const EdgeInsets.all(24),
            maxZoom: 8,
          )
        : null;

    return Stack(
      children: [
        FlutterMap(
          // 種別を変えたら地図を作り直す。表示する範囲が種別で変わるため。
          // 種別と中心のどちらが変わっても映す範囲が変わるので、作り直す。
          key: ValueKey('${kind?.name}-${widget.state.worldCenter.name}'),
          mapController: _controller,
          options: MapOptions(
            initialCameraFit: fit,
            // 全世界が対象の種別は、選んだ中心で世界全体を映す。
            initialCenter: MapStyle.centerOf(widget.state.worldCenter),
            initialZoom: minZoom,
            maxZoom: MapStyle.maxZoom,
            minZoom: minZoom,
            onPositionChanged: (camera, _) => _keepInsideWorld(camera, size),
            cameraConstraint:
                CameraConstraint.containCenter(bounds: MapStyle.cameraBounds),
            // 常に北を上に固定する。指で拡大縮小するときに地図が回ってしまい、
            // 「北がどっちか分からない」状態になるのを防ぐ。
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            // 何もない場所を触ったら選択を解除する。
            onTap: (tapPosition, point) => widget.state.select(null),
          ),
          children: [
            MapStyle.toTileLayer(),
            if (coverage != null && !coverage.global)
              _coverageLayer(context, coverage),
            MarkerLayer(
              markers: [
                // 深刻なものが上に重なるよう、軽い順に描く。
                for (final event in events.toList()
                  ..sort((a, b) => a.severity.level.compareTo(b.severity.level)))
                  _markerFor(event),
              ],
            ),
          ],
        ),
        if (coverage != null)
          Positioned(
            left: 8,
            top: 8,
            child: _CoverageLegend(coverage: coverage, kindLabel: kind!.labelJa),
          ),
        const Positioned(
          right: 4,
          bottom: 4,
          child: _AttributionLabel(text: MapStyle.attribution),
        ),
      ],
    );
  }

  /// 矩形の集まりを、全部が収まる1つの範囲にまとめる。
  LatLngBounds _boundsOf(List<CoverageBox> boxes) {
    var west = boxes.first.west;
    var south = boxes.first.south;
    var east = boxes.first.east;
    var north = boxes.first.north;
    for (final box in boxes.skip(1)) {
      west = math.min(west, box.west);
      south = math.min(south, box.south);
      east = math.max(east, box.east);
      north = math.max(north, box.north);
    }
    return LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  /// データを取得できない範囲をグレーで塗る。
  ///
  /// 何も描かないと「そこでは災害が起きていない」と読めてしまうため、
  /// 「ここは情報源が無い」ことを地図の上で見せる。
  Widget _coverageLayer(BuildContext context, Coverage coverage) {
    return PolygonLayer(
      polygons: [
        for (final box in coverage.gaps)
          Polygon(
            points: [
              LatLng(box.north, box.west),
              LatLng(box.north, box.east),
              LatLng(box.south, box.east),
              LatLng(box.south, box.west),
            ],
            color: Colors.grey.withValues(alpha: 0.5),
          ),
      ],
    );
  }

  Marker _markerFor(DisasterEvent event) {
    final size = EventStyle.markerSizeOf(event.severity);
    final selected = widget.state.selected?.id == event.id;

    return Marker(
      point: LatLng(event.latitude!, event.longitude!),
      width: size,
      height: size,
      child: GestureDetector(
        onTap: () => widget.state.select(event),
        child: Tooltip(
          message: event.title,
          child: Container(
            decoration: BoxDecoration(
              color: EventStyle.colorOf(event.severity).withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.black : Colors.white,
                width: selected ? 3 : 1.5,
              ),
            ),
            child: Icon(
              EventStyle.iconOf(event.kind),
              size: size * 0.55,
              color: EventStyle.onColorOf(event.severity),
            ),
          ),
        ),
      ),
    );
  }
}

/// グレーの意味と、取得範囲の但し書きを示す小さな凡例。
class _CoverageLegend extends StatelessWidget {
  const _CoverageLegend({required this.coverage, required this.kindLabel});

  final Coverage coverage;

  /// 選んでいる種別名。
  final String kindLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      if (coverage.hasNoSource)
        '$kindLabelの情報源がありません'
      else if (!coverage.global)
        '対象: ${coverage.areaLabel}',
      if (coverage.caution != null) coverage.caution!,
    ];
    if (lines.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              lines.join('\n'),
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttributionLabel extends StatelessWidget {
  const _AttributionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
