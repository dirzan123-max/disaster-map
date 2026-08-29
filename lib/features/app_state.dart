import 'package:flutter/foundation.dart';

import '../core/region.dart';
import '../data/disaster_repository.dart';
import '../domain/disaster_event.dart';
import '../domain/event_kind.dart';
import '../domain/severity.dart';
import 'settings/notification_settings.dart';

/// 画面全体で共有する状態。
///
/// 地域の切り替え・絞り込み・取得結果をここに集約し、
/// 各ウィジェットは ListenableBuilder で必要な部分だけを描き直す。
class AppState extends ChangeNotifier {
  AppState({required this.repository});

  final DisasterRepository repository;

  Region _region = Region.japan;
  Region get region => _region;

  DisasterSnapshot? _snapshot;
  DisasterSnapshot? get snapshot => _snapshot;

  bool _loading = false;
  bool get loading => _loading;

  NotificationSettings _settings = const NotificationSettings();
  NotificationSettings get settings => _settings;

  /// 表示する災害種別。空にはできない（何も出ない画面を作らないため）。
  Set<EventKind> _visibleKinds = EventKind.values.toSet();
  Set<EventKind> get visibleKinds => _visibleKinds;

  Severity _minimumSeverity = Severity.info;
  Severity get minimumSeverity => _minimumSeverity;

  /// 地図でフォーカスされているイベント（詳細シートの表示対象）。
  DisasterEvent? _selected;
  DisasterEvent? get selected => _selected;

  /// 絞り込み後のイベント。地図・リスト・件数表示がすべてこれを見る。
  List<DisasterEvent> get visibleEvents {
    final events = _snapshot?.events ?? const <DisasterEvent>[];
    return events
        .where((event) =>
            _visibleKinds.contains(event.kind) &&
            event.severity.level >= _minimumSeverity.level)
        .toList();
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
    final cached = await repository.loadCached(_region);
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
      _snapshot = await repository.fetch(_region);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setRegion(Region region) async {
    if (_region == region) return;
    _region = region;
    _selected = null;
    // 地域を変えた直後は前の地域の内容が残らないよう、まずキャッシュを描く。
    _snapshot = await repository.loadCached(region);
    notifyListeners();
    await refresh();
  }

  void toggleKind(EventKind kind) {
    final kinds = Set<EventKind>.from(_visibleKinds);
    if (!kinds.remove(kind)) kinds.add(kind);
    if (kinds.isEmpty) return;
    _visibleKinds = kinds;
    notifyListeners();
  }

  void setMinimumSeverity(Severity severity) {
    _minimumSeverity = severity;
    notifyListeners();
  }

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
