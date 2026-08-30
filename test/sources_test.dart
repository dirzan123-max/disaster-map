import 'dart:io';

import 'package:disaster_map/core/iso6709.dart';
import 'package:disaster_map/core/world_text_ja.dart';
import 'package:disaster_map/data/area_points.dart';
import 'package:disaster_map/data/country_index.dart';
import 'package:disaster_map/data/sources/eonet_source.dart';
import 'package:disaster_map/data/sources/jma_quake_source.dart';
import 'package:disaster_map/data/sources/jma_volcano_source.dart';
import 'package:disaster_map/data/sources/jma_warning_source.dart';
import 'package:disaster_map/data/sources/jma_warning_xml_source.dart';
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

/// 世界版の和訳。同梱の国データから国名の対応表を作る。
final WorldTextJa worldText = WorldTextJa(
  CountryIndex.parse(File('assets/countries.json').readAsStringSync())
      .japaneseNameByEnglish,
);

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

  group('気象庁 気象警報（防災情報XML）', () {
    final source = JmaWarningXmlSource(
      areaPoints: parseAreaPoints(
        File('assets/jma_class10_points.json').readAsStringSync(),
      ),
    );

    test('フィードから発表XMLの場所を、府県ごとに最新1件だけ取り出す', () {
      final urls = source.parseFeed(fixture('jma_warning_feed.xml'));
      expect(urls, isNotEmpty);
      expect(urls.every((url) => url.contains('VPWW')), isTrue);
      // 同じ府県が何度も更新されるため、重複していないこと。
      final offices = urls
          .map((url) => url.split('/').last.split('_')[3])
          .toList();
      expect(offices.toSet().length, offices.length);
    });

    test('発表XMLから、発表時刻・警報の種類・区域を取り出せる', () {
      final events = source.parseReport(fixture('jma_warning_report.xml'));
      expect(events, isNotEmpty);
      expect(events.every((e) => e.kind == EventKind.weatherWarning), isTrue);

      // bosai の JSON と違い、いつ発表されたかが入っている。
      // これが無いと期間で絞り込めない。
      final reported = events.first.occurredAt;
      expect(reported.isUtc, isTrue);
      expect(reported.year, greaterThan(2000));

      // 区域コードは bosai と同じなので、同梱の代表点表で座標を引ける。
      expect(events.any((e) => e.hasLocation), isTrue);
      expect(events.every((e) => !e.title.startsWith('区域')), isTrue);
    });

    test('警報が出ていない区域は落とす', () {
      final events = source.parseReport(fixture('jma_warning_report.xml'));
      expect(events.every((e) => e.details.isNotEmpty), isTrue);
    });

    test('壊れた XML でも落ちない', () {
      expect(source.parseReport('<not-xml'), isEmpty);
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

    test('検索API（24時間より前を遡る窓口）も同じ形で読める', () {
      final history = UsgsSource(text: worldText)
          .parse(fixture('usgs_fdsn_query.geojson'));
      expect(history, isNotEmpty);
      expect(history.every((event) => event.hasLocation), isTrue);
      expect(history.every((event) => event.occurredAt.isUtc), isTrue);
      expect(history.every((event) => event.id.startsWith('usgs-')), isTrue);
      // まとめフィードと ID 体系が同じなので、重なった分をまとめられる。
      expect(history.every((event) => (event.magnitude ?? 0) >= 5), isTrue);
    });

    test('検索APIの問い合わせ先に期間とマグニチュードが入る', () {
      final source = UsgsSource(historyMinimumMagnitude: 4.5);
      final url = source.historyEndpoint(DateTime.utc(2026, 7, 30)).toString();
      expect(url, contains('fdsnws/event/1/query'));
      expect(url, contains('starttime=2026-07-30T00:00:00.000Z'));
      expect(url, contains('minmagnitude=4.5'));
    });

    test('見出しと補足が日本語になっている', () {
      final japanese = UsgsSource(text: worldText)
          .parse(fixture('usgs_all_day.geojson'));
      expect(japanese.first.title, startsWith('M'));
      expect(japanese.any((e) => e.title.contains('の')), isTrue);
      expect(japanese.every((e) => !e.title.contains(' of ')), isTrue);
      expect(japanese.first.subtitle, contains('深さ'));
      expect(japanese.first.details, contains(startsWith('原文: ')));
    });
  });

  group('NASA EONET', () {
    final events = EonetSource().parse(fixture('eonet_events.json'));

    test('種別ごとに分類できている', () {
      expect(events, isNotEmpty);
      expect(events.every((e) => e.hasLocation), isTrue);
      expect(events.map((e) => e.kind).toSet(), isNotEmpty);
    });

    test('見出しと詳細が日本語になっている', () {
      final japanese =
          EonetSource(text: worldText).parse(fixture('eonet_events.json'));
      expect(japanese.any((e) => e.title.startsWith('山火事 ')), isTrue);
      expect(japanese.every((e) => !e.title.startsWith('Wildfire ')), isTrue);
      expect(japanese.first.details, contains(startsWith('種類: ')));
      // 「10000.0エーカー」ではなく「10000エーカー」と出す。
      expect(japanese.first.details.join(), isNot(contains('.0エーカー')));
    });

    test('時刻は発生・探知した時刻を使う（最新の観測時刻ではない）', () {
      // 「いつ起きたか」で絞り込めるようにするため。最新の観測時刻にすると、
      // 続いている限り常に「今」になってしまい、期間の絞り込みが効かない。
      final japanese =
          EonetSource(text: worldText).parse(fixture('eonet_events.json'));
      expect(japanese, isNotEmpty);
      // 継続中でも、時刻は過去のまま（＝期間で絞れる）。
      expect(
        japanese.every((event) => event.occurredAt.isBefore(DateTime.now().toUtc())),
        isTrue,
      );
      expect(japanese.every((event) => !event.isOngoing), isTrue);
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
