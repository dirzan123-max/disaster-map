import 'dart:io';

import 'package:disaster_map/core/world_text_ja.dart';
import 'package:disaster_map/data/country_filter.dart';
import 'package:disaster_map/data/country_index.dart';
import 'package:disaster_map/data/coverage.dart';
import 'package:disaster_map/domain/disaster_event.dart';
import 'package:disaster_map/domain/event_kind.dart';
import 'package:disaster_map/domain/severity.dart';
import 'package:disaster_map/domain/time_window.dart';
import 'package:disaster_map/features/settings/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// 同梱アセットをそのまま読む。生成物が壊れていればここで落ちる。
final CountryIndex countries =
    CountryIndex.parse(File('assets/countries.json').readAsStringSync());

DisasterEvent eventAt(
  DateTime occurredAt, {
  String? countryCode,
  Severity severity = Severity.severe,
  EventKind kind = EventKind.earthquake,
  bool ongoing = false,
}) =>
    DisasterEvent(
      isOngoing: ongoing,
      id: 'test-${occurredAt.toIso8601String()}-$countryCode',
      kind: kind,
      severity: severity,
      title: 'テスト',
      occurredAt: occurredAt,
      sourceName: 'テスト',
      countryCode: countryCode,
    );

void main() {
  group('期間の絞り込み', () {
    final now = DateTime.utc(2026, 8, 29, 12, 0);
    DateTime ago(Duration duration) => now.subtract(duration);

    test('直近30分は30分前までを含み、それより古いものを外す', () {
      const window = TimeWindow(maxAge: Duration(minutes: 30));
      expect(window.contains(ago(const Duration(minutes: 10)), now: now), isTrue);
      expect(window.contains(ago(const Duration(minutes: 29)), now: now), isTrue);
      expect(window.contains(ago(const Duration(minutes: 31)), now: now), isFalse);
    });

    test('1時間前から2時間前までは、その間だけを含む', () {
      const window = TimeWindow(
        minAge: Duration(hours: 1),
        maxAge: Duration(hours: 2),
      );
      expect(window.contains(ago(const Duration(minutes: 30)), now: now), isFalse);
      expect(window.contains(ago(const Duration(minutes: 90)), now: now), isTrue);
      expect(window.contains(ago(const Duration(hours: 3)), now: now), isFalse);
    });

    test('制限なしはいつのものでも通す', () {
      expect(
        TimeWindow.all.contains(ago(const Duration(days: 400)), now: now),
        isTrue,
      );
    });

    test('端末の時計が進んでいて未来の時刻になっても取りこぼさない', () {
      const window = TimeWindow(maxAge: Duration(minutes: 30));
      final future = now.add(const Duration(minutes: 5));
      expect(window.contains(future, now: now), isTrue);
      expect(window.containsForNotification(future, now: now), isTrue);
    });

    test('通知では下限を無視する（起きた直後の情報を落とさない）', () {
      const window = TimeWindow(
        minAge: Duration(hours: 1),
        maxAge: Duration(hours: 2),
      );
      final justNow = ago(const Duration(minutes: 1));
      expect(window.contains(justNow, now: now), isFalse);
      expect(window.containsForNotification(justNow, now: now), isTrue);
      // 上限より古いものは通知でも落とす。
      expect(
        window.containsForNotification(ago(const Duration(hours: 5)), now: now),
        isFalse,
      );
    });

    test('日をまたぐ長さも日本語で出す', () {
      expect(const TimeWindow(maxAge: Duration(days: 3)).label, '直近3日');
      expect(const TimeWindow(maxAge: Duration(days: 30)).label, '直近30日');
    });

    test('選択肢は「直近○○」だけを並べる（範囲は都度指定してもらう）', () {
      expect(TimeWindow.presets.first, TimeWindow.all);
      for (final window in TimeWindow.presets) {
        expect(window.minAge, Duration.zero);
      }
    });

    test('保存して読み直しても同じ条件になる', () {
      const custom = TimeWindow(
        minAge: Duration(hours: 1),
        maxAge: Duration(hours: 2),
      );
      for (final window in [...TimeWindow.presets, custom]) {
        expect(TimeWindow.fromJson(window.toJson()), window);
      }
    });

    test('表示名が日本語になっている', () {
      // 「全期間」と書くと無制限に見えるが、実際は配信元の範囲が上限。
      expect(TimeWindow.all.label, '制限なし');
      expect(const TimeWindow(maxAge: Duration(minutes: 30)).label, '直近30分');
      expect(const TimeWindow(maxAge: Duration(hours: 2)).label, '直近2時間');
      expect(
        const TimeWindow(
          minAge: Duration(hours: 1),
          maxAge: Duration(hours: 2),
        ).label,
        '1時間〜2時間前',
      );
    });
  });

  group('国の判定', () {
    test('同梱データに主要な国が揃っている', () {
      expect(countries.byCode.length, greaterThan(200));
      for (final code in ['JP', 'US', 'CN', 'TW', 'KR', 'CL', 'ID', 'PH']) {
        expect(countries[code], isNotNull, reason: '$code が無い');
      }
      // 台湾の ISO_A2 は "CN-TW" のため、中国と取り違えやすい。
      expect(countries['TW']!.nameEn, 'Taiwan');
      expect(countries['CN']!.nameEn, 'China');
    });

    test('陸上の座標を正しい国に割り当てる', () {
      expect(countries.resolve(35.68, 139.69)?.code, 'JP'); // 東京
      expect(countries.resolve(37.57, 126.98)?.code, 'KR'); // ソウル
      expect(countries.resolve(-33.45, -70.65)?.code, 'CL'); // サンティアゴ
      expect(countries.resolve(61.20, -149.90)?.code, 'US'); // アンカレジ
      expect(countries.resolve(14.60, 120.98)?.code, 'PH'); // マニラ
    });

    test('沿岸・近海のイベントは近い国に寄せる', () {
      // 日本の東方沖（陸から約 100km）。
      expect(countries.resolve(36.0, 142.5)?.code, 'JP');
    });

    test('どの国からも遠い外洋は null を返す', () {
      expect(countries.resolve(10.0, -140.0), isNull);
    });

    test('ひらがな・英語・国コードのどれでも検索できる', () {
      String? firstCode(String query) =>
          countries.search(query).firstOrNull?.code;
      expect(firstCode('にほん'), 'JP');
      expect(firstCode('日本'), 'JP');
      expect(firstCode('japan'), 'JP');
      expect(firstCode('jp'), 'JP');
      expect(countries.search('存在しない国'), isEmpty);
    });
  });

  group('英語テキストの和訳', () {
    final text = WorldTextJa(countries.japaneseNameByEnglish);

    test('USGS の見出しを方角・国名ごと訳す', () {
      expect(
        text.usgsTitle('M 4.3 - 10 km SSE of Ocotito, Mexico'),
        'M4.3 メキシコ Ocotito の南南東 10km',
      );
    });

    test('米国の州の略号を州名にする', () {
      expect(
        text.place('8km NW of The Geysers, CA'),
        '米国カリフォルニア州 The Geysers の北西 8km',
      );
    });

    test('海域の言い回しを訳す', () {
      expect(text.place('off the coast of Oregon'), '米国オレゴン州 の沖');
      expect(text.place('Fiji region'), 'フィジー 付近');
      expect(text.place('south of the Fiji Islands'), 'Fiji Islands の南方');
    });

    test('EONET の見出しを訳す', () {
      expect(
        text.eonetTitle('Telica Volcano, Nicaragua'),
        'Telica 火山（ニカラグア）',
      );
      expect(
        text.eonetTitle('Wildfire Calico, Humboldt, Nevada'),
        '山火事 Calico Humboldt 米国ネバダ州',
      );
      expect(text.eonetTitle('Tropical Storm Julio'), '熱帯低気圧 Julio');
    });

    test('訳せない固有名詞は原文のまま残す', () {
      expect(text.place('Somewhere Unknown'), 'Somewhere Unknown');
    });

    test('カテゴリと単位を訳す', () {
      expect(WorldTextJa.category('Wildfires'), '山火事');
      expect(WorldTextJa.unit('kts'), 'ノット');
      expect(WorldTextJa.unit(null), '');
    });
  });

  group('さかのぼれる範囲', () {
    test('種別ごとに、配信されている長さを持っている', () {
      expect(
        DataCoverage.historyOf(EventKind.earthquake),
        const Duration(days: 30),
      );
      // EONET は事象が起きた（探知された）時刻を持つので、期間で絞れる。
      expect(
        DataCoverage.historyOf(EventKind.wildfire),
        const Duration(days: 10),
      );
      expect(
        DataCoverage.historyOf(EventKind.storm),
        const Duration(days: 14),
      );
    });

    test('気象警報は上限を設けない（配信されているぶんがそのまま上限）', () {
      expect(DataCoverage.historyOf(EventKind.weatherWarning), isNull);
      // 上限が無いので、選択肢は全部出す。
      expect(TimeWindow.presetsWithin(null), TimeWindow.presets);
    });

    test('配信されていない長さは選択肢に出さない', () {
      final options =
          TimeWindow.presetsWithin(const Duration(days: 10)).toList();
      expect(options, contains(const TimeWindow(maxAge: Duration(days: 7))));
      expect(
        options,
        isNot(contains(const TimeWindow(maxAge: Duration(days: 15)))),
      );
      // 「制限なし」は残す（＝取れるぶん全部）。
      expect(options, contains(TimeWindow.all));
      // 上限が無いときは全部出す。
      expect(TimeWindow.presetsWithin(null), TimeWindow.presets);
    });
  });

  group('データの取得範囲', () {
    test('地震・火山・台風は全世界、山火事は米国のみ', () {
      expect(DataCoverage.of(EventKind.earthquake).global, isTrue);
      expect(DataCoverage.of(EventKind.volcano).global, isTrue);
      expect(DataCoverage.of(EventKind.storm).global, isTrue);

      final wildfire = DataCoverage.of(EventKind.wildfire);
      expect(wildfire.global, isFalse);
      expect(wildfire.areaLabel, '米国のみ');
    });

    test('気象警報と津波は日本のみ', () {
      // 地図が1つになったぶん、範囲の違いは種別ごとに示す必要がある。
      for (final kind in [EventKind.weatherWarning, EventKind.tsunami]) {
        final coverage = DataCoverage.of(kind);
        expect(coverage.global, isFalse, reason: kind.name);
        expect(coverage.boxes.single, DataCoverage.japanBox, reason: kind.name);
      }
    });

    test('情報源が無い種別は無い（すべて何かしら取れる）', () {
      for (final kind in EventKind.values) {
        expect(DataCoverage.of(kind).hasNoSource, isFalse, reason: kind.name);
      }
    });

    test('グレーに塗る範囲は、取得範囲と重ならず世界全体を覆う', () {
      final coverage = DataCoverage.of(EventKind.weatherWarning);
      final gaps = coverage.gaps;
      expect(gaps, isNotEmpty);

      for (final gap in gaps) {
        for (final box in coverage.boxes) {
          expect(gap.overlaps(box), isFalse);
        }
        // 経度 -180/180 は地図上で同じ位置に投影されるため、細かく割る。
        expect(gap.east - gap.west, lessThanOrEqualTo(Coverage.sliceWidth));
      }

      double area(CoverageBox box) =>
          (box.east - box.west) * (box.north - box.south);
      expect(
        gaps.fold<double>(0, (sum, gap) => sum + area(gap)),
        closeTo(area(Coverage.world) - area(DataCoverage.japanBox), 0.001),
      );
    });

    test('全世界が取得範囲ならグレーは出さない', () {
      expect(DataCoverage.of(EventKind.earthquake).gaps, isEmpty);
    });
  });

  group('通知の条件', () {
    final now = DateTime.now().toUtc();

    /// 全種別を「注意以上」にした設定。判定そのものを見るため。
    NotificationSettings settingsWith({
      CountryFilter countries = CountryFilter.none,
      TimeWindow timeWindow = TimeWindow.all,
    }) =>
        NotificationSettings(
          rules: NotificationRules({
            for (final kind in EventKind.values) kind: Severity.moderate,
          }),
          countries: countries,
          timeWindow: timeWindow,
        );

    test('通知そのものを切ると何も飛ばない', () {
      final settings = settingsWith().copyWith(enabled: false);
      expect(settings.matches(eventAt(now)), isFalse);
    });

    test('国を登録すると、その国のものだけが通知対象になる', () {
      final settings = settingsWith(countries: const CountryFilter(all: {'JP'}));
      expect(
        settings.matches(eventAt(now, countryCode: 'JP')),
        isTrue,
      );
      expect(
        settings.matches(eventAt(now, countryCode: 'US')),
        isFalse,
      );
    });

    test('国を特定できない情報は既定では通知する', () {
      final settings = settingsWith(countries: const CountryFilter(all: {'JP'}));
      expect(settings.matches(eventAt(now)), isTrue);

      final strict = settings.copyWith(
        countries: const CountryFilter(all: {'JP'}, includeUnknown: false),
      );
      expect(strict.matches(eventAt(now)), isFalse);
    });

    test('種別ごとに国を分けて指定できる', () {
      final settings = settingsWith(
        countries: const CountryFilter(
          perKind: true,
          byKind: {
            EventKind.earthquake: {'JP'},
            EventKind.storm: {'PH'},
          },
        ),
      );
      final quakeInPhilippines =
          eventAt(now, countryCode: 'PH', kind: EventKind.earthquake);
      final stormInPhilippines =
          eventAt(now, countryCode: 'PH', kind: EventKind.storm);
      expect(settings.matches(quakeInPhilippines), isFalse);
      expect(settings.matches(stormInPhilippines), isTrue);
    });

    test('まとめて／種別ごとを切り替えても、もう一方の指定は消えない', () {
      // 誤って切り替えたときに設定をやり直す羽目にならないよう、両方持っておく。
      const filter = CountryFilter(
        all: {'JP', 'US'},
        byKind: {
          EventKind.earthquake: {'CL'},
        },
      );
      final perKind = filter.copyWith(perKind: true);
      expect(perKind.forKind(EventKind.earthquake), {'CL'});
      expect(perKind.all, {'JP', 'US'});

      final back = perKind.copyWith(perKind: false);
      expect(back.forKind(EventKind.earthquake), {'JP', 'US'});
      expect(back.byKind[EventKind.earthquake], {'CL'});
    });

    test('情報源が一国に限られる種別は、国で絞らない', () {
      // 山火事は米国の消防データしか無い。国で絞っても意味が無いので素通しする。
      final settings = settingsWith(countries: const CountryFilter(all: {'JP'}));
      final wildfire =
          eventAt(now, countryCode: 'US', kind: EventKind.wildfire);
      expect(settings.matches(wildfire), isTrue);
      expect(CountryFilter.appliesTo(EventKind.wildfire), isFalse);
      expect(CountryFilter.selectableKinds, isNot(contains(EventKind.wildfire)));
    });

    test('期間の上限を過ぎた情報は通知しない', () {
      final settings = settingsWith(
        timeWindow: const TimeWindow(maxAge: Duration(minutes: 30)),
      );
      expect(settings.matches(eventAt(now)), isTrue);
      expect(
        settings.matches(
          eventAt(now.subtract(const Duration(hours: 2))),
        ),
        isFalse,
      );
    });

    test('継続中の情報でも、古ければ期間で外れる', () {
      // 「継続中だから期間の対象外」にすると、期間を変えても件数が変わらず
      // 絞り込みが壊れているように見える。継続中かどうかは表示の話に留める。
      final settings = settingsWith(
        timeWindow: const TimeWindow(maxAge: Duration(hours: 24)),
      );
      final old = now.subtract(const Duration(days: 90));
      expect(
        settings.matches(
          eventAt(old, kind: EventKind.weatherWarning, ongoing: true),
        ),
        isFalse,
      );
      expect(
        settings.matches(
          eventAt(now, kind: EventKind.weatherWarning, ongoing: true),
        ),
        isTrue,
      );
    });

    test('通知の深刻度は「注意以上」からしか選べない', () {
      // 軽微以上で通知すると、震度1・2 まで鳴り続けて役に立たなくなる。
      expect(Severity.filterOptions, contains(Severity.minor));
      expect(Severity.notifyOptions, isNot(contains(Severity.minor)));
      expect(Severity.minor.forNotification, Severity.moderate);
    });

    test('種別ごとに通知する深刻度を変えられる', () {
      const settings = NotificationSettings(
        rules: NotificationRules({
          EventKind.earthquake: Severity.severe,
          EventKind.tsunami: Severity.moderate,
        }),
      );
      // 地震は警戒以上、津波は注意から。火山は選んでいないので通知しない。
      expect(
        settings.matches(eventAt(now, severity: Severity.moderate)),
        isFalse,
      );
      expect(
        settings.matches(
          eventAt(now, severity: Severity.moderate, kind: EventKind.tsunami),
        ),
        isTrue,
      );
      expect(
        settings.matches(
          eventAt(now, severity: Severity.extreme, kind: EventKind.volcano),
        ),
        isFalse,
      );
    });

    test('地図を分けていた頃の保存形式も読める', () {
      // 日本・世界で別々に持っていた条件を、1つにまとめて読み替える。
      final restored = NotificationSettings.fromJson({
        'japan': {
          'enabled': true,
          'severityByKind': {'earthquake': 3, 'tsunami': 2},
        },
        'world': {
          'enabled': true,
          'severityByKind': {'earthquake': 2, 'storm': 3},
        },
      });
      // 同じ種別が両方にあれば、取りこぼさないよう緩い方を採る。
      expect(restored.rules.severityFor(EventKind.earthquake), Severity.moderate);
      expect(restored.rules.severityFor(EventKind.tsunami), Severity.moderate);
      expect(restored.rules.severityFor(EventKind.storm), Severity.severe);
      expect(restored.rules.severityFor(EventKind.volcano), isNull);
    });

    test('さらに前の保存形式（種別の集合＋ひとつのしきい値）も読める', () {
      final restored = NotificationSettings.fromJson({
        'japan': {
          'enabled': true,
          'minimumSeverity': 1,
          'kinds': ['earthquake', 'tsunami'],
        },
      });
      // 選べなくなった「軽微」は選択肢の中に丸める。
      expect(restored.rules.severityFor(EventKind.earthquake), Severity.moderate);
      expect(restored.rules.severityFor(EventKind.tsunami), Severity.moderate);
      expect(restored.rules.severityFor(EventKind.volcano), isNull);
    });

    test('深刻度が判定できなかった情報は「軽微」として扱う', () {
      // 画面の絞り込みでは拾える（下限が「軽微以上」から選べる）。
      expect(Severity.info.forFilter, Severity.minor);
      // 通知は「注意以上」からなので、判定できなかったものは鳴らない。
      expect(
        settingsWith().matches(
          eventAt(now, severity: Severity.info),
        ),
        isFalse,
      );
    });

    test('画面の深刻度は「軽微」から選べ、保存される', () {
      const settings = NotificationSettings(viewMinimumSeverity: Severity.severe);
      final restored = NotificationSettings.fromJson(settings.toJson());
      expect(restored.viewMinimumSeverity, Severity.severe);
      // 以前保存された「情報」は選択肢の中に丸める。
      expect(
        NotificationSettings.fromJson({'viewMinimumSeverity': 0})
            .viewMinimumSeverity,
        Severity.minor,
      );
    });

    test('保存して読み直しても条件が変わらない', () {
      const settings = NotificationSettings(
        countries: CountryFilter(
          perKind: true,
          all: {'JP'},
          byKind: {
            EventKind.earthquake: {'JP', 'US'},
          },
          includeUnknown: false,
        ),
        timeWindow: TimeWindow(
          minAge: Duration(hours: 1),
          maxAge: Duration(hours: 2),
        ),
      );
      final restored = NotificationSettings.fromJson(settings.toJson());
      expect(restored.countries.perKind, isTrue);
      expect(restored.countries.all, {'JP'});
      expect(restored.countries.forKind(EventKind.earthquake), {'JP', 'US'});
      expect(restored.countries.includeUnknown, isFalse);
      expect(restored.timeWindow, settings.timeWindow);
    });
  });
}
