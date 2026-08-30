"""Natural Earth の国境データから、国フィルタ用の同梱アセットを生成する。

生成物:
  assets/countries.json  国コード -> 日本語名・英語名・外接矩形・簡略化した国境

実行方法:
  python tool/build_countries.py

出典: Natural Earth (public domain) https://www.naturalearthdata.com/
  ne_50m_admin_0_countries.geojson（242の国と地域。日本語名 NAME_JA を含む）

アプリ実行時に取得しないのは、国境が滅多に変わらないため。
座標は 0.015 度で間引き・小数3桁に丸めており、
「どの国で起きたか」の判定に必要な精度だけを残している（地図の描画には使わない）。
"""

from __future__ import annotations

import io
import json
import math
import re
import urllib.request

SOURCE = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_countries.geojson"
)
USER_AGENT = "disaster-map-build/0.1 (personal portfolio app)"
OUTPUT = "assets/countries.json"

# 正式名称だけでは引けない、よく使われる呼び名。
# 検索欄に「アメリカ」「韓国」と打って出てこないと、国の登録で詰まるため。
ALIASES = {
    "JP": ["にほん", "ニホン", "ニッポン"],
    "US": ["アメリカ", "米国", "USA"],
    "CN": ["中国"],
    "TW": ["台湾"],
    "KR": ["韓国"],
    "KP": ["北朝鮮"],
    "GB": ["英国", "イギリス"],
    "TH": ["タイ"],
    "ZA": ["南アフリカ"],
    "AE": ["UAE"],
    "RU": ["ロシア連邦"],
    "NZ": ["ニュージーランド"],
    "AU": ["オーストラリア"],
}

# 間引きの強さ（度）。0.015 度 ≒ 1.7km。国の判定にはこれで十分。
TOLERANCE = 0.015
# これより小さい島は落とす（度^2）。0.01 ≒ 一辺 3km 四方。
MIN_RING_AREA = 0.001


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.loads(response.read().decode("utf-8"))


def simplify(points: list[tuple[float, float]], tolerance: float):
    """Douglas-Peucker で頂点を間引く。"""
    if len(points) < 3:
        return points

    first, last = points[0], points[-1]
    index, distance = 0, 0.0
    for i in range(1, len(points) - 1):
        d = perpendicular_distance(points[i], first, last)
        if d > distance:
            index, distance = i, d

    if distance <= tolerance:
        return [first, last]
    return simplify(points[: index + 1], tolerance)[:-1] + simplify(
        points[index:], tolerance
    )


def perpendicular_distance(point, start, end) -> float:
    (x, y), (x0, y0), (x1, y1) = point, start, end
    dx, dy = x1 - x0, y1 - y0
    if dx == 0 and dy == 0:
        return math.hypot(x - x0, y - y0)
    t = ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return math.hypot(x - (x0 + t * dx), y - (y0 + t * dy))


def ring_area(ring: list[tuple[float, float]]) -> float:
    area2 = 0.0
    for i in range(len(ring) - 1):
        area2 += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1]
    return abs(area2) / 2


def outer_rings(geometry: dict) -> list[list[tuple[float, float]]]:
    """各ポリゴンの外周だけを取り出す（穴は国の判定に影響しないため捨てる）。"""
    kind = geometry["type"]
    if kind == "Polygon":
        polygons = [geometry["coordinates"]]
    elif kind == "MultiPolygon":
        polygons = geometry["coordinates"]
    else:
        return []
    return [[(p[0], p[1]) for p in polygon[0]] for polygon in polygons]


def country_code(properties: dict) -> str | None:
    """ISO 3166-1 alpha-2 を優先して取り出す。

    ISO_A2 には台湾の "CN-TW" のような値も入っており、
    先頭2文字で切ると中国と衝突する。2文字の英字のときだけ採用する。
    """
    for key in ("ISO_A2", "ISO_A2_EH"):
        value = properties.get(key)
        if value and re.fullmatch(r"[A-Z]{2}", value):
            return value
    for key in ("ADM0_ISO", "ISO_A3"):
        value = properties.get(key)
        if value and re.fullmatch(r"[A-Z]{3}", value):
            return value
    return None


def main() -> None:
    features = fetch_json(SOURCE)["features"]
    countries: dict[str, dict] = {}
    # 同じ国コードで複数の地物が来る（オーストラリアとアシュモア・カルティエ諸島など）。
    # 領域は足し合わせ、名前は面積が最大の地物のものを採る。
    largest: dict[str, float] = {}

    for feature in features:
        properties = feature["properties"]
        code = country_code(properties)
        if code is None:
            continue

        rings = []
        for ring in outer_rings(feature["geometry"]):
            if ring_area(ring) < MIN_RING_AREA:
                continue
            reduced = simplify(ring, TOLERANCE)
            if len(reduced) < 4:
                continue
            rings.append(reduced)

        if not rings:
            # 面積の小さい島国は間引きで消えることがある。最大の島だけ残す。
            candidates = outer_rings(feature["geometry"])
            if not candidates:
                continue
            rings = [max(candidates, key=ring_area)]

        flat = []
        for ring in rings:
            flat.append([round(value, 3) for point in ring for value in point])

        area = sum(ring_area(ring) for ring in rings)
        existing = countries.get(code)
        if existing is None:
            existing = {"ja": "", "en": "", "rings": []}
            countries[code] = existing
            largest[code] = -1.0
        existing["rings"].extend(flat)
        if area > largest[code]:
            largest[code] = area
            existing["ja"] = properties["NAME_JA"]
            existing["en"] = properties["NAME"]

    for code, country in countries.items():
        rings = country["rings"]
        longitudes = [ring[i] for ring in rings for i in range(0, len(ring), 2)]
        latitudes = [ring[i] for ring in rings for i in range(1, len(ring), 2)]
        country["bbox"] = [
            min(longitudes),
            min(latitudes),
            max(longitudes),
            max(latitudes),
        ]
        if code in ALIASES:
            country["alias"] = ALIASES[code]

    with io.open(OUTPUT, "w", encoding="utf-8") as file:
        json.dump(countries, file, ensure_ascii=False, separators=(",", ":"))
    vertices = sum(len(r) // 2 for c in countries.values() for r in c["rings"])
    print(f"{OUTPUT}: {len(countries)} countries, {vertices} vertices")


if __name__ == "__main__":
    main()
