import '../core/app_http.dart';
import '../core/world_text_ja.dart';
import '../domain/disaster_event.dart';
import '../domain/event_kind.dart';
import 'area_points.dart';
import 'event_cache.dart';
import 'sources/disaster_source.dart';
import 'sources/eonet_source.dart';
import 'sources/jma_quake_source.dart';
import 'sources/jma_volcano_source.dart';
import 'sources/jma_warning_xml_source.dart';
import 'sources/p2p_quake_source.dart';
import 'sources/usgs_source.dart';

/// 取得結果。どのソースが失敗したかも一緒に返す。
///
/// 1つのソースが落ちても他の情報は出す。
/// ただし「今どの情報が欠けているか」は画面に必ず示す。
class DisasterSnapshot {
  const DisasterSnapshot({
    required this.events,
    required this.fetchedAt,
    this.failures = const [],
    this.staleKinds = const {},
    this.fromCache = false,
  });

  final List<DisasterEvent> events;

  /// この内容がいつ時点のものか（キャッシュ表示のときは保存時刻）。
  final DateTime fetchedAt;

  /// 取得に失敗したソースの名前と理由。
  final List<SourceFailure> failures;

  /// 配信が止まっている種別と、その最新の時刻。
  ///
  /// 取得そのものは成功しているのに中身が古い、という状態がありうる。
  /// 実際、気象庁の警報 API が3か月更新されていないことがあった。
  /// 黙って0件にすると「絞り込みのせい」と誤解されるため、別に持って画面に出す。
  final Map<EventKind, DateTime> staleKinds;

  final bool fromCache;

  bool get hasFailures => failures.isNotEmpty;
}

class SourceFailure {
  const SourceFailure(this.sourceName, this.reason);

  final String sourceName;
  final String reason;
}

/// すべてのデータソースをまとめて取得し、正規化する。
///
/// 画面側はこのクラスだけを見ればよく、どの API を何本叩いているかを知らない。
/// 地図は1つなので、日本の情報源と世界の情報源を常に両方見る。
class DisasterRepository {
  DisasterRepository({
    required this.assets,
    AppHttp? http,
    this.cache = const EventCache(),
  }) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 同梱している区域・火山の座標表。気象庁のソースが使う。
  final AreaAssets assets;
  final EventCache cache;

  List<DisasterSource> get sources => [
        P2pQuakeSource(http: _http),
        // 気象警報は防災情報XMLから取る（発表時刻が入っていて、期間で絞れる）。
        // Web からも叩ける（CORS 許可済み）。
        JmaWarningXmlSource(areaPoints: assets.class10Points, http: _http),
        JmaVolcanoSource(volcanoPoints: assets.volcanoPoints, http: _http),
        // 世界の配信元は英語のみ。取得した時点で日本語へ直しておき、
        // 画面・通知・Webhook のどこから見ても同じ日本語になるようにする。
        UsgsSource(http: _http, text: _text),
        EonetSource(http: _http, text: _text),
      ];

  late final WorldTextJa _text = WorldTextJa(
    assets.countries.japaneseNameByEnglish,
  );

  /// 気象庁から取れる種別。日本国内ではこちらを優先する。
  static const Set<EventKind> japanSourceKinds = {
    EventKind.earthquake,
    EventKind.tsunami,
    EventKind.weatherWarning,
    EventKind.volcano,
  };

  /// 世界を対象にした配信元の名前。日本国内の重複を外すときに使う。
  static const Set<String> worldSourceNames = {'USGS', 'NASA EONET'};

  /// 全ソースを並列に取得する。1つでも成功すればその結果を返す。
  Future<DisasterSnapshot> fetch() async {
    final results = await Future.wait(
      sources.map((source) async {
        try {
          return _SourceResult(source.sourceName, await source.fetch(), null);
        } catch (error) {
          return _SourceResult(source.sourceName, const [], error);
        }
      }),
    );

    final events = <DisasterEvent>[];
    final failures = <SourceFailure>[];
    for (final result in results) {
      if (result.error != null) {
        failures.add(SourceFailure(result.sourceName, '${result.error}'));
      }
      events.addAll(result.events);
    }

    // 国内の地震が1件も取れていないときだけ、気象庁の一覧へ切り替える。
    // 一次情報源だが応答が大きいため、平常時は叩かない。
    final hasJapanQuake = events.any(
      (event) =>
          event.kind == EventKind.earthquake &&
          !worldSourceNames.contains(event.sourceName),
    );
    if (failures.isNotEmpty && !hasJapanQuake) {
      try {
        events.addAll(await JmaQuakeSource(http: _http).fetch());
        failures.add(const SourceFailure('P2P地震情報', '気象庁の一覧に切り替えました'));
      } catch (_) {
        // 代替も失敗した場合は、失敗の記録だけを残してキャッシュ表示に委ねる。
      }
    }

    if (events.isEmpty && failures.isNotEmpty) {
      final cached = await cache.load();
      if (cached != null) {
        return DisasterSnapshot(
          events: cached.events,
          fetchedAt: cached.savedAt,
          failures: failures,
          fromCache: true,
        );
      }
    }

    final normalized =
        _withoutJapanDuplicates(_withCountries(_deduplicate(events)))
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    if (normalized.isNotEmpty) {
      await cache.save(normalized);
    }

    return DisasterSnapshot(
      events: normalized,
      fetchedAt: DateTime.now().toUtc(),
      failures: failures,
      staleKinds: _staleKinds(normalized),
    );
  }

  /// 毎日のように更新されるはずの情報が、いつまでも古いままでないか。
  ///
  /// 火山の噴火警戒レベルのように、何か月も変わらないのが普通の情報もあるため、
  /// 「更新され続けるはずの種別」だけを見る。
  static const Map<EventKind, Duration> _freshnessLimits = {
    EventKind.weatherWarning: Duration(days: 3),
  };

  static Map<EventKind, DateTime> _staleKinds(List<DisasterEvent> events) {
    final now = DateTime.now().toUtc();
    final stale = <EventKind, DateTime>{};
    _freshnessLimits.forEach((kind, limit) {
      final times = [
        for (final event in events)
          if (event.kind == kind) event.occurredAt,
      ];
      if (times.isEmpty) return;
      final latest = times.reduce((a, b) => a.isAfter(b) ? a : b);
      if (now.difference(latest) > limit) stale[kind] = latest;
    });
    return stale;
  }

  /// 起動直後に前回の内容をすぐ描くためのキャッシュ読み出し。
  Future<DisasterSnapshot?> loadCached() async {
    final cached = await cache.load();
    if (cached == null) return null;
    return DisasterSnapshot(
      events: cached.events,
      fetchedAt: cached.savedAt,
      fromCache: true,
    );
  }

  /// 日本国内について、世界の配信元から来た重複を外す。
  ///
  /// 日本国内の地震・火山は気象庁（震度・噴火警戒レベルつき）の方が細かく、
  /// USGS からも同じ出来事が来る。両方出すと同じ地震が2つ並ぶため、
  /// 気象庁が扱っている種別に限って、世界の配信元のぶんを落とす。
  /// 気象庁が扱っていない台風・山火事は、日本国内でもそのまま残す。
  static List<DisasterEvent> _withoutJapanDuplicates(
    List<DisasterEvent> events,
  ) =>
      [
        for (final event in events)
          if (event.countryCode != 'JP' ||
              !worldSourceNames.contains(event.sourceName) ||
              !japanSourceKinds.contains(event.kind))
            event,
      ];

  /// 座標から国を判定して各イベントに持たせる。
  ///
  /// 判定はここで一度だけ行う。画面の絞り込みのたびに国境を調べ直すと、
  /// イベント数×国数の計算が毎回走って描画が重くなる。
  List<DisasterEvent> _withCountries(List<DisasterEvent> events) {
    if (assets.countries.byCode.isEmpty) return events;
    return [
      for (final event in events)
        if (!event.hasLocation)
          event
        else
          event.withCountry(
            assets.countries.resolve(event.latitude!, event.longitude!)?.code,
          ),
    ];
  }

  static List<DisasterEvent> _deduplicate(List<DisasterEvent> events) {
    final byId = <String, DisasterEvent>{};
    for (final event in events) {
      byId.putIfAbsent(event.id, () => event);
    }
    return byId.values.toList();
  }
}

class _SourceResult {
  const _SourceResult(this.sourceName, this.events, this.error);

  final String sourceName;
  final List<DisasterEvent> events;
  final Object? error;
}
