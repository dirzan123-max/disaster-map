import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/country_filter.dart';
import '../../data/coverage.dart';
import '../../domain/disaster_event.dart';
import '../../domain/event_kind.dart';
import '../../domain/severity.dart';
import '../../domain/time_window.dart';
import '../map/map_style.dart';

/// 種別ごとの通知条件。
///
/// 「地震は警戒以上、津波は注意報から」のように種別で重さが違うため、
/// ひとつのしきい値にまとめず、種別ごとに持つ。
/// 入っていない種別は通知しない。
class NotificationRules {
  const NotificationRules(this.severityByKind);

  final Map<EventKind, Severity> severityByKind;

  /// 既定。日本で起きやすいものを中心に、鳴りすぎない範囲で入れておく。
  /// 台風・山火事は件数が多いので既定では切っておく。
  static const NotificationRules initial = NotificationRules({
    EventKind.earthquake: Severity.severe,
    EventKind.tsunami: Severity.moderate,
    EventKind.weatherWarning: Severity.severe,
    EventKind.volcano: Severity.severe,
  });

  /// 設定画面に並べる種別。情報源がある種別だけを出す。
  static List<EventKind> get availableKinds => [
        for (final kind in EventKind.values)
          if (!DataCoverage.of(kind).hasNoSource) kind,
      ];

  /// 種別の対象範囲の但し書き（「米国のみ」など）。全世界なら null。
  static String? areaNoteFor(EventKind kind) {
    final coverage = DataCoverage.of(kind);
    return coverage.global ? null : coverage.areaLabel;
  }

  /// この種別の下限。通知しない設定なら null。
  Severity? severityFor(EventKind kind) => severityByKind[kind];

  bool get notifiesNothing => severityByKind.isEmpty;

  bool matches(DisasterEvent event) {
    final minimum = severityByKind[event.kind];
    return minimum != null && event.severity.forFilter.level >= minimum.level;
  }

  /// 1つの種別だけを変える。null を渡すとその種別は通知しなくなる。
  NotificationRules withKind(EventKind kind, Severity? severity) {
    final next = Map<EventKind, Severity>.from(severityByKind);
    if (severity == null) {
      next.remove(kind);
    } else {
      next[kind] = severity;
    }
    return NotificationRules(next);
  }

  Map<String, dynamic> toJson() => {
        for (final entry in severityByKind.entries)
          entry.key.name: entry.value.level,
      };

  static NotificationRules fromJson(Object? stored) {
    final byKind = <EventKind, Severity>{};
    if (stored is Map) {
      stored.forEach((name, level) {
        final kind =
            EventKind.values.where((each) => each.name == name).firstOrNull;
        if (kind == null || level is! num) return;
        // 選べなくなった深刻度が残っていても、選択肢の中に丸めて読む。
        byKind[kind] = Severity.fromLevel(level.toInt()).forNotification;
      });
    }
    // 全部外した設定は通知が一切飛ばず事故のもとなので、既定へ戻す。
    return byKind.isEmpty ? initial : NotificationRules(byKind);
  }

  /// 地図を日本版・世界版に分けていた頃の保存形式から読み替える。
  ///
  /// 地域ごとに持っていた条件を1つにまとめる。同じ種別が両方にあれば、
  /// 通知を取りこぼさないよう緩い方（軽い深刻度）を採る。
  static NotificationRules? fromLegacy(Map<String, dynamic> json) {
    final merged = <EventKind, Severity>{};
    for (final key in ['japan', 'world']) {
      final region = json[key];
      if (region is! Map) continue;
      if (region['enabled'] == false) continue;

      final byKind = <EventKind, Severity>{};
      final stored = region['severityByKind'];
      if (stored is Map) {
        stored.forEach((name, level) {
          final kind =
              EventKind.values.where((each) => each.name == name).firstOrNull;
          if (kind != null && level is num) {
            byKind[kind] = Severity.fromLevel(level.toInt()).forNotification;
          }
        });
      } else if (region['kinds'] is List) {
        // さらに前の形式（種別の集合＋ひとつのしきい値）。
        final minimum = Severity.fromLevel(
          (region['minimumSeverity'] as num?)?.toInt() ?? Severity.severe.level,
        ).forNotification;
        for (final name in region['kinds'] as List) {
          final kind =
              EventKind.values.where((each) => each.name == name).firstOrNull;
          if (kind != null) byKind[kind] = minimum;
        }
      }

      byKind.forEach((kind, severity) {
        final current = merged[kind];
        if (current == null || severity.level < current.level) {
          merged[kind] = severity;
        }
      });
    }
    return merged.isEmpty ? null : NotificationRules(merged);
  }
}

/// 通知を出す条件と、業務システムへの連携先。
///
/// Android のバックグラウンド処理からも読むため、
/// UI の状態とは切り離して端末に保存する。
/// 画面の絞り込み（期間・国・深刻度）も、通知と条件を共有する分をここに置く。
class NotificationSettings {
  const NotificationSettings({
    this.enabled = true,
    this.realtime = false,
    this.rules = NotificationRules.initial,
    this.timeWindow = const TimeWindow(maxAge: Duration(hours: 24)),
    this.countries = CountryFilter.none,
    this.viewMinimumSeverity = Severity.minor,
    this.worldCenter = WorldCenter.japan,
    this.webhookUrl,
    this.webhookFormat = WebhookFormat.slack,
  });

  /// 通知そのものを受け取るか。種別ごとの設定より上位の切り替え。
  final bool enabled;

  /// 地震の発表を待たずに受け取る常駐監視を使うか。
  ///
  /// 既定は切ってある。通知バーに居座り、電池も食うため、
  /// 必要な人が自分で入れる形にしている。
  final bool realtime;

  /// 種別ごとの通知条件。
  final NotificationRules rules;

  /// さかのぼる期間。画面の絞り込みと共有し、選んだ内容を端末に覚えておく。
  ///
  /// 人によって「常に直近24時間だけ見たい」「30日をまとめて見たい」が
  /// 分かれるため、種別ごとの既定は持たず、前回の選択をそのまま使う。
  /// 通知では下限（「1時間前から」）を無視し、古すぎる情報だけを落とす。
  final TimeWindow timeWindow;

  /// 対象にする国・地域。画面の絞り込みと共有する。
  final CountryFilter countries;

  /// 画面（地図・一覧）で出す深刻度の下限。
  ///
  /// 通知側の下限（[NotificationRules.severityByKind]）とは別に持つ。画面を
  /// 見やすくするために下限を上げたら通知まで止まった、という事故を避けるため。
  /// 選んだ値は覚えておき、次に開いたときも同じ条件で始まる。
  final Severity viewMinimumSeverity;

  /// 世界地図をどこを中心に見せるか。地図の見た目だけの設定。
  final WorldCenter worldCenter;

  /// Slack / Teams / Discord の Incoming Webhook URL。
  /// 設定されていれば、端末通知と同時に業務チャンネルへも送る。
  final String? webhookUrl;

  final WebhookFormat webhookFormat;

  bool get hasWebhook => (webhookUrl ?? '').trim().isNotEmpty;

  /// このイベントが、その地域の通知条件を満たすか。
  ///
  /// 端末通知・Webhook・Web版のプレビューがすべてこの判定を共有するため、
  /// 「画面に見えている条件」と「実際に飛ぶ通知」が必ず一致する。
  bool matches(DisasterEvent event) =>
      enabled &&
      rules.matches(event) &&
      timeWindow.containsForNotification(event.occurredAt) &&
      countries.matches(event);

  NotificationSettings copyWith({
    bool? enabled,
    bool? realtime,
    NotificationRules? rules,
    TimeWindow? timeWindow,
    CountryFilter? countries,
    Severity? viewMinimumSeverity,
    WorldCenter? worldCenter,
    String? webhookUrl,
    WebhookFormat? webhookFormat,
  }) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        realtime: realtime ?? this.realtime,
        rules: rules ?? this.rules,
        timeWindow: timeWindow ?? this.timeWindow,
        countries: countries ?? this.countries,
        viewMinimumSeverity: viewMinimumSeverity ?? this.viewMinimumSeverity,
        worldCenter: worldCenter ?? this.worldCenter,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        webhookFormat: webhookFormat ?? this.webhookFormat,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'realtime': realtime,
        'rules': rules.toJson(),
        'timeWindow': timeWindow.toJson(),
        'countries': countries.toJson(),
        'viewMinimumSeverity': viewMinimumSeverity.level,
        'worldCenter': worldCenter.name,
        'webhookUrl': webhookUrl,
        'webhookFormat': webhookFormat.name,
      };

  static NotificationSettings fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        enabled: json['enabled'] as bool? ?? true,
        realtime: json['realtime'] as bool? ?? false,
        // 地域ごとに分けていた頃の保存形式も読み替える。
        rules: json['rules'] == null
            ? (NotificationRules.fromLegacy(json) ?? NotificationRules.initial)
            : NotificationRules.fromJson(json['rules']),
        timeWindow: json['timeWindow'] == null
            ? const TimeWindow(maxAge: Duration(hours: 24))
            : TimeWindow.fromJson(
                (json['timeWindow'] as Map).cast<String, dynamic>(),
              ),
        countries: CountryFilter.fromJson(
          (json['countries'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        // 以前は「情報」も選べた。選択肢から外したため、読み込み時に丸める
        // （選べない値が入ったままだと設定画面の選択肢が壊れる）。
        viewMinimumSeverity: Severity.fromLevel(
          (json['viewMinimumSeverity'] as num?)?.toInt() ?? 1,
        ).forFilter,
        worldCenter: WorldCenter.values.firstWhere(
          (center) => center.name == json['worldCenter'],
          orElse: () => WorldCenter.japan,
        ),
        webhookUrl: json['webhookUrl'] as String?,
        webhookFormat: WebhookFormat.values.firstWhere(
          (format) => format.name == json['webhookFormat'],
          orElse: () => WebhookFormat.slack,
        ),
      );

  static const String _storageKey = 'notification_settings';

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(toJson()));
  }

  static Future<NotificationSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = preferences.getString(_storageKey);
    if (payload == null) return const NotificationSettings();
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return const NotificationSettings();
      return fromJson(decoded);
    } on FormatException {
      return const NotificationSettings();
    }
  }
}

/// Webhook のペイロード形式。業務で使われる3つに対応する。
enum WebhookFormat {
  slack,
  teams,
  discord;

  String get label => switch (this) {
        WebhookFormat.slack => 'Slack',
        WebhookFormat.teams => 'Microsoft Teams',
        WebhookFormat.discord => 'Discord',
      };
}
