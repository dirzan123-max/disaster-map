import 'dart:io';
import 'dart:math' as math;

import 'package:disaster_map/data/area_points.dart';
import 'package:disaster_map/data/country_filter.dart';
import 'package:disaster_map/data/country_index.dart';
import 'package:disaster_map/data/disaster_repository.dart';
import 'package:disaster_map/data/sources/disaster_source.dart';
import 'package:disaster_map/features/map/map_style.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:disaster_map/domain/disaster_event.dart';
import 'package:disaster_map/domain/event_kind.dart';
import 'package:disaster_map/domain/severity.dart';
import 'package:disaster_map/domain/time_window.dart';
import 'package:disaster_map/features/app_state.dart';
import 'package:disaster_map/features/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 決まった内容を返すだけの取得先。テストでは通信しない。
class FakeRepository extends DisasterRepository {
  FakeRepository(this.events) : super(assets: AreaAssets.empty);

  final List<DisasterEvent> events;

  @override
  Future<DisasterSnapshot> fetch() async =>
      DisasterSnapshot(events: events, fetchedAt: DateTime.now().toUtc());

  @override
  Future<DisasterSnapshot?> loadCached() async => null;
}

Future<AppState> stateWith(List<DisasterEvent> events) async {
  final state = AppState(repository: FakeRepository(events));
  await state.init();
  return state;
}

DisasterEvent sample({
  required String id,
  required EventKind kind,
  required Severity severity,
  required Duration age,
  String? countryCode,
}) =>
    DisasterEvent(
      id: id,
      kind: kind,
      severity: severity,
      title: '$id のできごと',
      occurredAt: DateTime.now().toUtc().subtract(age),
      sourceName: 'テスト',
      latitude: 35.0,
      longitude: 139.0,
      countryCode: countryCode,
    );

/// 決まったイベントを返すだけのデータソース。
class FakeSource extends DisasterSource {
  FakeSource(this.events);

  final List<DisasterEvent> events;

  @override
  String get sourceName => 'テスト';

  @override
  Future<List<DisasterEvent>> fetch() async => events;
}

/// 取得先だけ差し替えた本物のリポジトリ。国の判定と重複除外はそのまま通す。
class FakeSourceRepository extends DisasterRepository {
  FakeSourceRepository(this.events)
      : super(
          assets: AreaAssets(
            class10Points: const {},
            volcanoPoints: const {},
            areaNames: const {},
            countries: CountryIndex.parse(
              File('assets/countries.json').readAsStringSync(),
            ),
          ),
        );

  final List<DisasterEvent> events;

  @override
  List<DisasterSource> get sources => [FakeSource(events)];
}

DisasterEvent located({
  required String id,
  required EventKind kind,
  required double latitude,
  required double longitude,
  String sourceName = 'テスト',
}) =>
    DisasterEvent(
      id: id,
      kind: kind,
      severity: Severity.severe,
      title: id,
      occurredAt: DateTime.now().toUtc(),
      sourceName: sourceName,
      latitude: latitude,
      longitude: longitude,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('日本国内の重複を外す', () {
    test('日本の地震は気象庁のぶんだけ残し、USGS のぶんは外す', () async {
      final repository = FakeSourceRepository([
        located(
          id: 'jma-tokyo',
          kind: EventKind.earthquake,
          latitude: 35.68,
          longitude: 139.69,
          sourceName: '気象庁',
        ),
        located(
          id: 'usgs-tokyo',
          kind: EventKind.earthquake,
          latitude: 35.68,
          longitude: 139.69,
          sourceName: 'USGS',
        ),
        located(
          id: 'usgs-tokyo-storm',
          kind: EventKind.storm,
          latitude: 35.68,
          longitude: 139.69,
          sourceName: 'NASA EONET',
        ),
        located(
          id: 'usgs-chile',
          kind: EventKind.earthquake,
          latitude: -33.45,
          longitude: -70.65,
          sourceName: 'USGS',
        ),
      ]);

      final snapshot = await repository.fetch();
      final ids = snapshot.events.map((event) => event.id).toSet();
      // 同じ地震が2つ並ばないよう、詳しい気象庁のぶんを残す。
      expect(ids, contains('jma-tokyo'));
      expect(ids, isNot(contains('usgs-tokyo')));
      // 気象庁が扱っていない台風は、日本国内でもそのまま残す。
      expect(ids, contains('usgs-tokyo-storm'));
      expect(ids, contains('usgs-chile'));
    });
  });

  group('地図の縮小の下限', () {
    test('世界地図が2枚見えるところまで縮まない', () {
      const screen = Size(400, 700);
      final zoom = MapStyle.fitZoom(screen);
      // このズームで世界1周がちょうど画面幅になる。
      // 地図は東西に繰り返し描かれるので、これ以上縮めると2枚並んで見える。
      expect(256 * math.pow(2, zoom), closeTo(screen.width, 0.5));
    });

    MapCamera cameraAt(double longitude, double zoom, Size screen) => MapCamera(
          crs: const Epsg3857(),
          center: LatLng(0, longitude),
          zoom: zoom,
          rotation: 0,
          nonRotatedSize: screen,
        );

    test('一番縮小したときは、選んだ中心から動かせない', () {
      // 中心だけを縛る方式では、世界1枚ぶん横へ流せて「2枚分」に見えていた。
      const screen = Size(400, 700);
      final zoom = MapStyle.fitZoom(screen);

      for (final world in WorldCenter.values) {
        final corrected =
            MapStyle.clampLongitude(cameraAt(10, zoom, screen), screen.width, world);
        expect(corrected, isNotNull, reason: world.name);
        expect(
          MapStyle.shiftLongitude(corrected!.longitude, world),
          closeTo(0, 0.01),
          reason: world.name,
        );

        // 中心そのものにいるときは動かさない。
        expect(
          MapStyle.clampLongitude(
            cameraAt(world.longitude, zoom, screen),
            screen.width,
            world,
          ),
          isNull,
          reason: world.name,
        );
      }
    });

    test('拡大していれば、窓の中を自由に動かせる', () {
      const screen = Size(400, 700);
      // 世界が画面の4倍の幅になるズーム。画面は90度ぶんしか映らない。
      final zoom = MapStyle.fitZoom(screen) + 2;

      // 日本中心の窓は 東経140 ± 180、つまり 西経40 から 東経320（＝西経40）。
      // ハワイ（西経157）は窓の中なので動かさない。
      expect(
        MapStyle.clampLongitude(
          cameraAt(-157, zoom, screen),
          screen.width,
          WorldCenter.japan,
        ),
        isNull,
      );
      // 大西洋（西経30）は継ぎ目の向こう側なので、窓の端まで戻される。
      final corrected = MapStyle.clampLongitude(
        cameraAt(-30, zoom, screen),
        screen.width,
        WorldCenter.japan,
      );
      expect(corrected, isNotNull);
    });

    test('日本中心とイギリス中心で、映る位置が変わる', () {
      expect(MapStyle.centerOf(WorldCenter.japan).longitude, 140);
      expect(MapStyle.centerOf(WorldCenter.greenwich).longitude, 0);
    });
  });

  testWidgets('主画面が組み上がり、絞り込みの見出しが出る', (tester) async {
    final state = await stateWith([
      sample(
        id: 'quake',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(minutes: 5),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: HomePage(state: state)));
    await tester.pump();

    expect(find.text('災害情報マップ'), findsOneWidget);
    expect(find.text('地震'), findsOneWidget);
    expect(find.text('深刻度: 軽微以上'), findsOneWidget);
    // 何も選んでいないときの既定は直近24時間。
    expect(find.text('期間: 直近24時間'), findsOneWidget);
    // 地図は1つ。日本／世界の切り替えは無い。
    expect(find.text('世界'), findsNothing);
  });

  testWidgets('国を絞り込んでいることが帯に出る', (tester) async {
    final state = await stateWith([
      sample(
        id: 'quake',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(minutes: 5),
      ),
    ]);
    await state.setCountryFilter(const CountryFilter(all: {'JP', 'US'}));

    await tester.pumpWidget(MaterialApp(home: HomePage(state: state)));
    await tester.pump();

    // 国の指定は設定画面に移したので、絞り込み中であることは帯で知らせる。
    expect(find.textContaining('国: 2か国に限定中'), findsOneWidget);
    expect(find.textContaining('国:'), findsOneWidget);
  });

  testWidgets('種別は1つだけ選べる', (tester) async {
    final state = await stateWith([
      sample(
        id: 'quake',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(minutes: 5),
      ),
      sample(
        id: 'fire',
        kind: EventKind.wildfire,
        severity: Severity.moderate,
        age: const Duration(minutes: 5),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(home: HomePage(state: state)));
    await tester.pump();

    // 何も触っていないときは、取得できた種別の先頭が選ばれている。
    expect(state.selectedKind, EventKind.earthquake);
    expect(state.visibleEvents.single.id, 'quake');

    await tester.tap(find.widgetWithText(ChoiceChip, '山火事'));
    await tester.pump();
    expect(state.selectedKind, EventKind.wildfire);
    expect(state.visibleEvents.single.id, 'fire');

    await tester.tap(find.widgetWithText(ChoiceChip, '地震'));
    await tester.pump();
    expect(state.visibleEvents.single.id, 'quake');
  });

  test('選んだ期間は次に開いたときも使われる', () async {
    final events = [
      sample(
        id: 'quake',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(days: 5),
      ),
    ];

    final first = await stateWith(events);
    // 既定の24時間では5日前の地震は出ない。
    expect(first.visibleEvents, isEmpty);
    await first.setTimeWindow(const TimeWindow(maxAge: Duration(days: 7)));
    expect(first.visibleEvents, isNotEmpty);

    // 同じ端末で開き直しても、選んだ期間が残っている。
    final again = await stateWith(events);
    expect(again.timeWindow, const TimeWindow(maxAge: Duration(days: 7)));
    expect(again.visibleEvents, isNotEmpty);
  });

  test('配信が止まっている種別は、そのことが分かる', () async {
    // 気象庁の警報 API が3か月更新されていないことが実際にあった。
    // 取得は成功しているのに中身が古い、という状態を黙って0件にしない。
    final repository = FakeSourceRepository([
      DisasterEvent(
        id: 'warning',
        kind: EventKind.weatherWarning,
        severity: Severity.severe,
        title: '大雨警報',
        occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 90)),
        sourceName: '気象庁',
        latitude: 35.0,
        longitude: 139.0,
        isOngoing: true,
      ),
    ]);

    final snapshot = await repository.fetch();
    expect(snapshot.staleKinds[EventKind.weatherWarning], isNotNull);

    final state = AppState(repository: repository);
    await state.init();
    expect(state.staleSince, isNotNull);
    // 期間の絞り込みでは落ちるが、止まっていることは画面に出る。
    expect(state.visibleEvents, isEmpty);
  });

  test('継続中の情報でも、古ければ期間で消える', () async {
    final state = await stateWith([
      DisasterEvent(
        id: 'warning',
        kind: EventKind.weatherWarning,
        severity: Severity.severe,
        title: '大雨警報',
        // 気象庁の警報は、最後に発表された時刻のまま何か月も続くことがある。
        occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 90)),
        sourceName: '気象庁',
        latitude: 35.0,
        longitude: 139.0,
        isOngoing: true,
      ),
    ]);

    expect(state.timeWindow, const TimeWindow(maxAge: Duration(hours: 24)));
    // 90日前に更新された警報は、直近24時間の絞り込みからは外れる。
    expect(state.visibleEvents, isEmpty);

    await state.setTimeWindow(TimeWindow.all);
    expect(state.visibleEvents.single.id, 'warning');
  });

  test('期間と国の絞り込みが一覧に効く', () async {
    final state = await stateWith([
      sample(
        id: 'now-jp',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(minutes: 10),
        countryCode: 'JP',
      ),
      sample(
        id: 'old-us',
        kind: EventKind.earthquake,
        severity: Severity.severe,
        age: const Duration(hours: 3),
        countryCode: 'US',
      ),
    ]);

    expect(state.visibleEvents.length, 2);

    await state.setTimeWindow(const TimeWindow(maxAge: Duration(hours: 1)));
    expect(state.visibleEvents.single.id, 'now-jp');

    await state.setTimeWindow(TimeWindow.all);
    await state.setCountryFilter(const CountryFilter(all: {'US'}));
    expect(state.visibleEvents.single.id, 'old-us');
    // 種別は自動で選ばれるため、絞り込みの結果が空でも例外にならない。
    await state.setCountryFilter(const CountryFilter(all: {'CL'}));
    expect(state.visibleEvents, isEmpty);
  });
}
