import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  /// 地域を切り替えたときに地図の位置も合わせるため、前回の地域を覚えておく。
  late var _lastRegion = widget.state.region;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncRegion() {
    if (_lastRegion == widget.state.region) return;
    _lastRegion = widget.state.region;
    final style = MapStyle.of(_lastRegion);
    // build 中に地図を動かせないため、フレーム確定後に移動する。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.move(style.center, style.zoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncRegion();
    final style = MapStyle.of(widget.state.region);
    final events =
        widget.state.visibleEvents.where((event) => event.hasLocation).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: style.center,
            initialZoom: style.zoom,
            maxZoom: style.maxZoom,
            minZoom: 1,
            // 何もない場所を触ったら選択を解除する。
            onTap: (tapPosition, point) => widget.state.select(null),
          ),
          children: [
            style.toTileLayer(),
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
        Positioned(
          right: 4,
          bottom: 4,
          child: _AttributionLabel(text: style.attribution),
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
