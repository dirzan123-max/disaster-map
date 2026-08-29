import 'dart:io';

import 'package:disaster_map/core/iso6709.dart';
import 'package:disaster_map/data/area_points.dart';
import 'package:disaster_map/data/sources/eonet_source.dart';
import 'package:disaster_map/data/sources/jma_quake_source.dart';
import 'package:disaster_map/data/sources/jma_volcano_source.dart';
import 'package:disaster_map/data/sources/jma_warning_source.dart';
import 'package:disaster_map/data/sources/p2p_quake_source.dart';
import 'package:disaster_map/data/sources/usgs_source.dart';
import 'package:disaster_map/domain/event_kind.dart';
import 'package:disaster_map/domain/severity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 実際の API 応答を保存したものを読む。
///
/// 取得先が仕様を変えたときに気づけるよう、フィクスチャは
/// tool/refresh_fixtures.sh で取り直してコミットする。
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('ISO 6709', () {
    test('気象庁の震源座標を緯度・経度・深さへ分解する', () {
      final point = parseIso6709('+41.3+139.5-10000/');
      expect(point, isNotNull);
      expect(point!.latitude, 41.3);
      expect(point.longitude, 139.5);
      expect(point.depthKm, 10);
    });

    test('南半球・西半球の符号を保つ', () {
      final point = parseIso6709('-33.5-070.7-33000/');
      expect(point!.latitude, -33.5);
      expect(point.longitude, -70.7);
    });

    test('壊れた値は null を返す', () {
      expect(parseIso6709(null), isNull);
      expect(parseIso6709(''), isNull);
      expect(parseIso6709('+41.3/'), isNull);
      expect(parseIso6709('+999.9+999.9/'), isNull);
    });
  });

  group('P2P地震情報', () {
    final events = P2pQuakeSource().parse(fixture('p2p_history.json'));

    test('地震イベントを取り出せる', () {
      expect(events, isNotEmpty);
      expect(events.every((e) => e.kind == EventKind.earthquake ||
          e.kind == EventKind.tsunami), isTrue);
    });

    test('ID が一意で、再取得しても変わらない形式である', () {
      final ids = events.map((e) => e.id).toSet();
      expect(ids.length, events.length);
      expect(events.first.id, startsWith('p2p-'));
    });

    test('日本時間を UTC へ直している', () {
      // フィクスチャは JST の文字列。UTC に直すと必ず 9 時間前になる。
      for (final event in events) {
        expect(event.occurredAt.isUtc, isTrue);
      }
    });

    test('座標があるイベントは日本周辺に収まる', () {
      final located = events.where((e) => e.hasLocation);
      expect(located, isNotEmpty);
      for (final event in located) {
        expect(event.latitude!, inInclusiveRange(20, 50));
        expect(event.longitude!, inInclusiveRange(120, 155));
      }
    });

    test('震度から深刻度を決めている', () {
      expect(Severity.fromJmaScale(70), Severity.extreme);
      expect(Severity.fromJmaScale(45), Severity.severe);
      expect(Severity.fromJmaScale(30), Severity.moderate);
      expect(Severity.fromJmaScale(10), Severity.minor);
    });
  });

  group('気象庁 地震一覧（代替ソース）', () {
    final events = JmaQuakeSource().parse(fixture('jma_quake_list.json'));

    test('続報が並んでいても地震1件につき1つにまとめる', () {
      expect(events, isNotEmpty);
      final ids = events.map((e) => e.id).toSet();
      expect(ids.length, events.length);
    });

    test('震度表記を階級コードへ直す', () {
      expect(JmaQuakeSource.scaleOfIntensityLabel('5-'), 45);
      expect(JmaQuakeSource.scaleOfIntensityLabel('6+'), 60);
      expect(JmaQuakeSource.scaleOfIntensityLabel('7'), 70);
      expect(JmaQuakeSource.scaleOfIntensityLabel('不明'), 0);
    });
  });

  group('気象庁 気象警報', () {
    final points = parseAreaPoints(
        File('assets/jma_class10_points.json').readAsStringSync());
    final events = JmaWarningSource(areaPoints: points)
        .parse(fixture('jma_warning_map.json'));

    test('発表中の警報だけを取り出す', () {
      expect(events, isNotEmpty);
      expect(events.every((e) => e.kind == EventKind.weatherWarning), isTrue);
      expect(events.every((e) => e.details.isNotEmpty), isTrue);
    });

    test('すべての区域に座標が付く（同梱の代表点表で引ける）', () {
      expect(events.every((e) => e.hasLocation), isTrue);
    });

    test('区域名が「区域NNNNNN」のままになっていない', () {
      expect(events.any((e) => e.title.startsWith('区域')), isFalse);
    });

    test('未知のコードでも情報を落とさない', () {
      final unknown = JmaWarningSource.kindOf('99');
      expect(unknown.name, contains('99'));
      expect(unknown.severity, Severity.moderate);
    });
  });

  group('気象庁 噴火警報', () {
    final points = parseAreaPoints(
        File('assets/jma_volcano_points.json').readAsStringSync());
    final events = JmaVolcanoSource(volcanoPoints: points)
        .parse(fixture('jma_volcano_warning.json'));

    test('火山コードから座標を引けている', () {
      expect(events, isNotEmpty);
      expect(events.every((e) => e.hasLocation), isTrue);
      expect(events.every((e) => e.kind == EventKind.volcano), isTrue);
    });

    test('噴火警戒レベルの語から深刻度を決める', () {
      expect(JmaVolcanoSource.severityOfStatus('居住地域厳重警戒'), Severity.extreme);
      expect(JmaVolcanoSource.severityOfStatus('入山危険'), Severity.severe);
      expect(JmaVolcanoSource.severityOfStatus('火口周辺危険'), Severity.moderate);
      expect(
          JmaVolcanoSource.severityOfStatus('活火山であることに留意'), Severity.minor);
    });
  });

  group('USGS', () {
    final events = UsgsSource().parse(fixture('usgs_all_day.geojson'));

    test('GeoJSON の [経度, 緯度] を取り違えていない', () {
      expect(events, isNotEmpty);
      for (final event in events) {
        expect(event.latitude!, inInclusiveRange(-90, 90));
        expect(event.longitude!, inInclusiveRange(-180, 180));
      }
    });

    test('マグニチュードから深刻度を決めている', () {
      expect(Severity.fromMagnitude(7.5), Severity.extreme);
      expect(Severity.fromMagnitude(6.1), Severity.severe);
      expect(Severity.fromMagnitude(4.6), Severity.moderate);
      expect(Severity.fromMagnitude(1.2), Severity.minor);
      expect(Severity.fromMagnitude(null), Severity.info);
    });

    test('発生時刻を UTC で持つ', () {
      expect(events.every((e) => e.occurredAt.isUtc), isTrue);
    });
  });

  group('NASA EONET', () {
    final events = EonetSource().parse(fixture('eonet_events.json'));

    test('種別ごとに分類できている', () {
      expect(events, isNotEmpty);
      expect(events.every((e) => e.hasLocation), isTrue);
      expect(events.map((e) => e.kind).toSet(), isNotEmpty);
    });

    test('カテゴリを災害種別へ写像する', () {
      expect(EonetSource.kindOfCategory('wildfires'), EventKind.wildfire);
      expect(EonetSource.kindOfCategory('volcanoes'), EventKind.volcano);
      expect(EonetSource.kindOfCategory('severeStorms'), EventKind.storm);
      expect(EonetSource.kindOfCategory('floods'), EventKind.flood);
      expect(EonetSource.kindOfCategory('unknown'), EventKind.other);
    });
  });
}
