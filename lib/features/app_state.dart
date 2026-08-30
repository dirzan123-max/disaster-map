import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/country_filter.dart';
import '../data/country_index.dart';
import '../data/coverage.dart';
import '../data/disaster_repository.dart';
import '../domain/disaster_event.dart';
import '../domain/event_kind.dart';
import '../domain/severity.dart';
import '../domain/time_window.dart';
import 'map/map_style.dart';
import 'settings/notification_settings.dart';

/// 画面全体で共有する状態。
///
/// 地域の切り替え・絞り込み・取得結果をここに集約し、
/// 各ウィジェットは ListenableBuilder で必要な部分だけを描き直す。
class AppState extends ChangeNotifier {
  AppState({required this.repository});

  final DisasterRepository repository;

  DisasterSnapshot? _snapshot;
  DisasterSnapshot? get snapshot => _snapshot;

  bool _loading = false;
  bool get loading => _loading;

  NotificationSettings _settings = const NotificationSettings();
  NotificationSettings get settings => _settings;

  /// 表示する災害種別。1種別ずつ切り替える。
  ///
  /// 明示的に選ぶまでは null にしておき、取得できた種別の先頭を選んだ扱いにする
  /// （地域を切り替えても、その地域に無い種別が選ばれたままにならない）。
  EventKind? _selectedKind;

  /// 実際に表示している種別。取得結果が空のときだけ null。
  EventKind? get selectedKind {
    final kinds = availableKinds;
    if (kinds.isEmpty) return null;
    final selected = _selectedKind;
    return selected != null && kinds.contains(selected) ? selected : kinds.first;
  }

  /// 深刻度の下限。既定は「軽微以上」で、選んだ値は端末に残る。
  Severity get minimumSeverity => _settings.viewMinimumSeverity;

  /// さかのぼる期間と国の絞り込みは通知にも効くため、保存する設定側に持つ。
  /// 一度選べば次に開いたときも同じ期間で始まる。
  TimeWindow get timeWindow => _settings.timeWindow;

  /// 表示中の種別を、実際にどこまでさかのぼれるか。null なら「今出ているぶんだけ」。
  Duration? get historyLimit => DataCoverage.historyOf(selectedKind);

  /// 期間ボタンに出す文字。
  /// 「制限なし」は無制限ではなく配信されているぶんが上限なので、
  /// その長さをここで見せる（細かい説明を読ませずに済むように）。
  String get timeWindowLabel {
    final limit = historyLimit;
    if (!timeWindow.isUnbounded || limit == null) return timeWindow.label;
    return 'すべて（最大${TimeWindow.spanLabel(limit)}）';
  }

  /// 配信されていない長さが選ばれていたら、取れる範囲まで縮める。
  ///
  /// 「直近30日」で山火事（10日ぶんしか無い）を見ると、
  /// 絞り込みが効いていないのか情報が無いのか分からなくなるため。
  void _clampTimeWindow() {
    final limit = historyLimit;
    final current = timeWindow.maxAge;
    if (limit == null || current == null || current <= limit) return;
    unawaited(setTimeWindow(TimeWindow(minAge: timeWindow.minAge, maxAge: limit)));
  }
  CountryFilter get countryFilter => _settings.countries;

  /// 世界地図をどこを中心に見せるか。
  WorldCenter get worldCenter => _settings.worldCenter;

  Future<void> setWorldCenter(WorldCenter center) =>
      updateSettings(_settings.copyWith(worldCenter: center));

  /// 国の一覧・国境。国の検索画面と、絞り込みの表示名に使う。
  CountryIndex get countries => repository.assets.countries;

  /// 地図でフォーカスされているイベント（詳細シートの表示対象）。
  DisasterEvent? _selected;
  DisasterEvent? get selected => _selected;

  /// 絞り込み後のイベント。地図・リスト・件数表示がすべてこれを見る。
  List<DisasterEvent> get visibleEvents {
    final events = _snapshot?.events ?? const <DisasterEvent>[];
    // 経過時間の判定は 1 件ごとに現在時刻を取り直さず、揃えておく。
    final now = DateTime.now().toUtc();
    final kind = selectedKind;
    return events
        .where((event) =>
            event.kind == kind &&
            event.severity.forFilter.level >= minimumSeverity.level &&
            timeWindow.contains(event.occurredAt, now: now) &&
            _settings.countries.matches(event))
        .toList();
  }

  /// 表示中の種別の配信が止まっているなら、その最新時刻。
  DateTime? get staleSince => _snapshot?.staleKinds[selectedKind];

  /// 取得できた情報に実際に含まれる種別。絞り込みの選択肢に使う。
  List<EventKind> get availableKinds {
    final kinds = {
      for (final event in _snapshot?.events ?? const <DisasterEvent>[])
        event.kind,
    }.toList();
    kinds.sort((a, b) => a.index.compareTo(b.index));
    return kinds;
  }

  /// 現在の通知設定に照らして「今なら通知が飛ぶ」イベント。
  ///
  /// Web 版の通知プレビューと、Android の実通知が同じ判定を使う。
  List<DisasterEvent> get notifiableEvents => (_snapshot?.events ?? const [])
      .where(_settings.matches)
      .toList();

  Future<void> init() async {
    _settings = await NotificationSettings.load();
    // 前回の内容をまず描いてから、最新の取得を始める。
    final cached = await repository.loadCached();
    if (cached != null) {
      _snapshot = cached;
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _snapshot = await repository.fetch();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 表示する種別を切り替える。
  void selectKind(EventKind kind) {
    _selectedKind = kind;
    _clampTimeWindow();
    notifyListeners();
  }

  Future<void> setMinimumSeverity(Severity severity) =>
      updateSettings(_settings.copyWith(viewMinimumSeverity: severity));

  /// さかのぼる期間を変える。通知にも同じ条件が使われ、端末に保存される。
  Future<void> setTimeWindow(TimeWindow window) =>
      updateSettings(_settings.copyWith(timeWindow: window));

  /// 対象の国を変える。通知にも同じ条件が使われる。
  Future<void> setCountryFilter(CountryFilter filter) =>
      updateSettings(_settings.copyWith(countries: filter));

  void select(DisasterEvent? event) {
    _selected = event;
    notifyListeners();
  }

  Future<void> updateSettings(NotificationSettings settings) async {
    _settings = settings;
    notifyListeners();
    await settings.save();
  }
}
