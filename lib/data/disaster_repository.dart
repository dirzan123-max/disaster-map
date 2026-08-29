import '../core/app_http.dart';
import '../core/region.dart';
import '../domain/disaster_event.dart';
import 'area_points.dart';
import 'event_cache.dart';
import 'sources/disaster_source.dart';
import 'sources/eonet_source.dart';
import 'sources/jma_quake_source.dart';
import 'sources/jma_volcano_source.dart';
import 'sources/jma_warning_source.dart';
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
    this.fromCache = false,
  });

  final List<DisasterEvent> events;

  /// この内容がいつ時点のものか（キャッシュ表示のときは保存時刻）。
  final DateTime fetchedAt;

  /// 取得に失敗したソースの名前と理由。
  final List<SourceFailure> failures;

  final bool fromCache;

  bool get hasFailures => failures.isNotEmpty;
}

class SourceFailure {
  const SourceFailure(this.sourceName, this.reason);

  final String sourceName;
  final String reason;
}

/// 地域に応じてデータソースを選び、まとめて取得・正規化する。
///
/// 画面側はこのクラスだけを見ればよく、どの API を何本叩いているかを知らない。
class DisasterRepository {
  DisasterRepository({
    required this.assets,
    AppHttp? http,
    this.cache = const EventCache(),
  }) : _http = http ?? AppHttp();

  final AppHttp _http;

  /// 同梱している区域・火山の座標表。日本版のソースが使う。
  final AreaAssets assets;
  final EventCache cache;

  List<DisasterSource> sourcesFor(Region region) => switch (region) {
        Region.japan => [
            P2pQuakeSource(http: _http),
            JmaWarningSource(areaPoints: assets.class10Points, http: _http),
            JmaVolcanoSource(volcanoPoints: assets.volcanoPoints, http: _http),
          ],
        Region.world => [
            UsgsSource(http: _http),
            EonetSource(http: _http),
          ],
      };

  /// 全ソースを並列に取得する。1つでも成功すればその結果を返す。
  Future<DisasterSnapshot> fetch(Region region) async {
    final sources = sourcesFor(region);
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

    // 日本版で地震が1件も取れていないときだけ、気象庁の一覧へ切り替える。
    // 一次情報源だが応答が大きいため、平常時は叩かない。
    if (region == Region.japan && failures.isNotEmpty && events.isEmpty) {
      try {
        events.addAll(await JmaQuakeSource(http: _http).fetch());
        failures.add(const SourceFailure('P2P地震情報', '気象庁の一覧に切り替えました'));
      } catch (_) {
        // 代替も失敗した場合は、失敗の記録だけを残してキャッシュ表示に委ねる。
      }
    }

    if (events.isEmpty && failures.isNotEmpty) {
      final cached = await cache.load(region);
      if (cached != null) {
        return DisasterSnapshot(
          events: cached.events,
          fetchedAt: cached.savedAt,
          failures: failures,
          fromCache: true,
        );
      }
    }

    final deduplicated = _deduplicate(events)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    if (deduplicated.isNotEmpty) {
      await cache.save(region, deduplicated);
    }

    return DisasterSnapshot(
      events: deduplicated,
      fetchedAt: DateTime.now().toUtc(),
      failures: failures,
    );
  }

  /// 起動直後に前回の内容をすぐ描くためのキャッシュ読み出し。
  Future<DisasterSnapshot?> loadCached(Region region) async {
    final cached = await cache.load(region);
    if (cached == null) return null;
    return DisasterSnapshot(
      events: cached.events,
      fetchedAt: cached.savedAt,
      fromCache: true,
    );
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
