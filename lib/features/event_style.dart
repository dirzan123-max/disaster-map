import 'package:flutter/material.dart';

import '../domain/event_kind.dart';
import '../domain/severity.dart';

/// 深刻度と災害種別の見せ方をここに集約する。
///
/// 地図のピン・リストの行・凡例・通知が同じ色と記号を使うことで、
/// 「赤は何を意味するのか」を利用者が一度覚えれば済むようにしている。
class EventStyle {
  const EventStyle._();

  /// 深刻度の色。信号の連想（青緑 → 黄 → 橙 → 赤）に沿わせ、
  /// 明暗どちらのテーマでも白文字が読める濃さに揃えている。
  static Color colorOf(Severity severity) => switch (severity) {
        Severity.info => const Color(0xFF546E7A),
        Severity.minor => const Color(0xFF00838F),
        Severity.moderate => const Color(0xFFF9A825),
        Severity.severe => const Color(0xFFEF6C00),
        Severity.extreme => const Color(0xFFC62828),
      };

  /// 深刻度の文字色（色の上に載せる前景）。
  static Color onColorOf(Severity severity) =>
      severity == Severity.moderate ? Colors.black87 : Colors.white;

  static IconData iconOf(EventKind kind) => switch (kind) {
        EventKind.earthquake => Icons.crisis_alert,
        EventKind.tsunami => Icons.tsunami,
        EventKind.weatherWarning => Icons.thunderstorm,
        EventKind.volcano => Icons.volcano,
        EventKind.wildfire => Icons.local_fire_department,
        EventKind.flood => Icons.flood,
        EventKind.storm => Icons.cyclone,
        EventKind.other => Icons.info_outline,
      };

  /// 地図上のピンの大きさ。深刻なものほど大きく、重なっても目に入るようにする。
  static double markerSizeOf(Severity severity) => switch (severity) {
        Severity.info => 24,
        Severity.minor => 26,
        Severity.moderate => 30,
        Severity.severe => 36,
        Severity.extreme => 42,
      };
}
