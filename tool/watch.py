"""定期監視して、しきい値を超えた災害情報を業務チャットへ通知する。

アプリを入れていない相手（対策本部のチャンネル）へ届けるための経路。
GitHub Actions の cron から呼ぶ想定で、サーバーを持たずに運用できる。

    python tool/watch.py

環境変数:
    WEBHOOK_URL       Slack / Teams / Discord の Incoming Webhook（必須）
    WEBHOOK_FORMAT    slack | teams | discord（既定: slack）
    REGION            japan | world（既定: japan）
    MIN_SEVERITY      0=情報 1=軽微 2=注意 3=警戒 4=重大（既定: 3）
    STATE_FILE        通知済みIDの保存先（既定: .watch_state.json）
    DRY_RUN           1 なら送信せず内容を表示するだけ

深刻度の決め方はアプリ側（lib/domain/severity.dart）と同じ基準にしてある。
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field

USER_AGENT = "disaster-map-watch/0.1 (personal portfolio app)"
TIMEOUT = 20

SEVERITY_LABELS = ["情報", "軽微", "注意", "警戒", "重大"]

P2P_URL = "https://api.p2pquake.net/v2/history?codes=551&codes=552&limit=30"
JMA_WARNING_URL = "https://www.jma.go.jp/bosai/warning/data/warning/map.json"
USGS_URL = (
    "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson"
)

# 気象警報のうち、通知に値するもの（警報以上）だけを持つ。
# 全コードはアプリ側 lib/data/sources/jma_warning_source.dart にある。
JMA_WARNING_NAMES = {
    "32": ("暴風雪特別警報", 4),
    "33": ("大雨特別警報", 4),
    "35": ("暴風特別警報", 4),
    "36": ("大雪特別警報", 4),
    "37": ("波浪特別警報", 4),
    "38": ("高潮特別警報", 4),
    "02": ("暴風雪警報", 3),
    "03": ("大雨警報", 3),
    "04": ("洪水警報", 3),
    "05": ("暴風警報", 3),
    "06": ("大雪警報", 3),
    "07": ("波浪警報", 3),
    "08": ("高潮警報", 3),
}

JMA_SCALE_LABELS = {
    10: "1", 20: "2", 30: "3", 40: "4",
    45: "5弱", 50: "5強", 55: "6弱", 60: "6強", 70: "7",
}


@dataclass
class Event:
    id: str
    severity: int
    title: str
    occurred_at: str
    source: str
    details: list[str] = field(default_factory=list)


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def severity_of_scale(scale: int) -> int:
    if scale >= 55:
        return 4
    if scale >= 45:
        return 3
    if scale >= 30:
        return 2
    if scale >= 10:
        return 1
    return 0


def severity_of_magnitude(magnitude: float | None) -> int:
    if magnitude is None:
        return 0
    if magnitude >= 7.0:
        return 4
    if magnitude >= 6.0:
        return 3
    if magnitude >= 4.5:
        return 2
    return 1


def collect_japan() -> list[Event]:
    events: list[Event] = []

    for entry in fetch_json(P2P_URL):
        if entry.get("code") == 551:
            quake = entry.get("earthquake") or {}
            hypocenter = quake.get("hypocenter") or {}
            scale = quake.get("maxScale") or -1
            magnitude = hypocenter.get("magnitude")
            severity = (
                severity_of_scale(scale) if scale >= 10
                else severity_of_magnitude(magnitude)
            )
            title = hypocenter.get("name") or "震源不明"
            if magnitude and magnitude > 0:
                title += f" M{magnitude:.1f}"
            if scale >= 10:
                title += f" 最大震度{JMA_SCALE_LABELS.get(scale, '不明')}"
            events.append(Event(
                id=f"p2p-eq-{entry.get('id')}",
                severity=severity,
                title=title,
                occurred_at=quake.get("time", ""),
                source="気象庁 / P2P地震情報",
            ))
        elif entry.get("code") == 552 and not entry.get("cancelled"):
            grades = {"MajorWarning": 4, "Warning": 3, "Watch": 2}
            areas = entry.get("areas") or []
            severity = max(
                (grades.get(area.get("grade"), 0) for area in areas), default=0)
            events.append(Event(
                id=f"p2p-ts-{entry.get('id')}",
                severity=severity,
                title="津波予報が発表されています",
                occurred_at=entry.get("time", ""),
                source="気象庁 / P2P地震情報",
                details=[area.get("name", "") for area in areas],
            ))

    for office in fetch_json(JMA_WARNING_URL):
        reported_at = office.get("reportDatetime", "")
        area_types = office.get("areaTypes") or []
        if not area_types:
            continue
        for area in area_types[0].get("areas", []):
            active = []
            for warning in area.get("warnings", []):
                code = warning.get("code")
                if warning.get("status") in ("解除", "発表警報・注意報はなし"):
                    continue
                if code in JMA_WARNING_NAMES:
                    active.append(JMA_WARNING_NAMES[code])
            if not active:
                continue
            name, severity = max(active, key=lambda item: item[1])
            events.append(Event(
                id=f"jma-warn-{area.get('code')}-{name}",
                severity=severity,
                title=f"区域{area.get('code')} {name}",
                occurred_at=reported_at,
                source="気象庁",
                details=[item[0] for item in active],
            ))

    return events


def collect_world() -> list[Event]:
    events: list[Event] = []
    for feature in fetch_json(USGS_URL).get("features", []):
        properties = feature.get("properties") or {}
        magnitude = properties.get("mag")
        events.append(Event(
            id=f"usgs-{feature.get('id')}",
            severity=severity_of_magnitude(magnitude),
            title=properties.get("title", "Earthquake"),
            occurred_at=str(properties.get("time", "")),
            source="USGS",
            details=[properties.get("url", "")],
        ))
    return events


def build_payload(event: Event, fmt: str) -> dict:
    headline = f"【{SEVERITY_LABELS[event.severity]}】{event.title}"
    body = "\n".join([
        f"発表: {event.occurred_at}",
        f"出典: {event.source}",
        *[detail for detail in event.details if detail],
    ])
    if fmt == "teams":
        return {
            "@type": "MessageCard",
            "@context": "https://schema.org/extensions",
            "summary": headline,
            "themeColor": ["546E7A", "546E7A", "F9A825", "EF6C00", "C62828"][
                event.severity],
            "title": headline,
            "text": body.replace("\n", "\n\n"),
        }
    if fmt == "discord":
        return {"content": f"{headline}\n{body}"}
    return {"text": f"{headline}\n{body}"}


def post(url: str, payload: dict) -> bool:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            return 200 <= response.status < 300
    except urllib.error.HTTPError as error:
        print(f"送信に失敗しました: {error.code} {error.reason}", file=sys.stderr)
        return False


def load_state(path: str) -> set[str]:
    try:
        with open(path, encoding="utf-8") as file:
            return set(json.load(file))
    except (OSError, json.JSONDecodeError):
        return set()


def save_state(path: str, ids: set[str]) -> None:
    # 無限に増やさないよう、直近1000件だけ残す。
    with open(path, "w", encoding="utf-8") as file:
        json.dump(sorted(ids)[-1000:], file, ensure_ascii=False)


def main() -> int:
    webhook_url = os.environ.get("WEBHOOK_URL", "").strip()
    dry_run = os.environ.get("DRY_RUN") == "1"
    if not webhook_url and not dry_run:
        print("WEBHOOK_URL が設定されていません", file=sys.stderr)
        return 1

    region = os.environ.get("REGION", "japan")
    fmt = os.environ.get("WEBHOOK_FORMAT", "slack")
    minimum = int(os.environ.get("MIN_SEVERITY", "3"))
    state_path = os.environ.get("STATE_FILE", ".watch_state.json")

    events = collect_japan() if region == "japan" else collect_world()
    seen = load_state(state_path)

    targets = [
        event for event in events
        if event.severity >= minimum and event.id not in seen
    ]
    print(f"取得 {len(events)}件 / 条件に合う未通知 {len(targets)}件")

    for event in targets:
        payload = build_payload(event, fmt)
        if dry_run:
            print(json.dumps(payload, ensure_ascii=False))
        elif not post(webhook_url, payload):
            # 送信できなかったものは通知済みにせず、次回に持ち越す。
            continue
        seen.add(event.id)

    save_state(state_path, seen)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
