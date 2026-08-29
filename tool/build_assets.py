"""気象庁の公開データからアプリ同梱アセットを生成する。

生成物:
  assets/jma_class10_points.json  警報を地図に出すための一次細分区域(153件)の代表点
  assets/jma_area_names.json      区域コード -> 名称(全階層)。詳細表示で使う
  assets/jma_volcano_points.json  火山コード -> 名称・座標(120件)

実行方法:
  python tool/build_assets.py

出典: 気象庁 https://www.jma.go.jp/bosai/
アプリ実行時にこれらを取得しないのは、名称・区域が滅多に変わらないため。
更新が必要になったら、このスクリプトを再実行してコミットする。
"""

from __future__ import annotations

import io
import json
import urllib.request

CLASS10_GEOJSON = "https://www.jma.go.jp/bosai/common/const/geojson/class10s.json"
AREA_MASTER = "https://www.jma.go.jp/bosai/common/const/area.json"
VOLCANO_LIST = "https://www.jma.go.jp/bosai/volcano/const/volcano_list.json"
USER_AGENT = "disaster-map-build/0.1 (personal portfolio app)"


def fetch_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def ring_area_and_centroid(ring: list[list[float]]) -> tuple[float, float, float]:
    """多角形の符号付き面積と重心を返す。ring は [lon, lat] の並び。"""
    area2 = 0.0
    cx = 0.0
    cy = 0.0
    for i in range(len(ring) - 1):
        x0, y0 = ring[i][0], ring[i][1]
        x1, y1 = ring[i + 1][0], ring[i + 1][1]
        cross = x0 * y1 - x1 * y0
        area2 += cross
        cx += (x0 + x1) * cross
        cy += (y0 + y1) * cross
    if area2 == 0:
        # 面積が潰れている場合は頂点の平均で代用する
        n = max(len(ring) - 1, 1)
        return 0.0, sum(p[0] for p in ring[:n]) / n, sum(p[1] for p in ring[:n]) / n
    return abs(area2 / 2), cx / (3 * area2), cy / (3 * area2)


def representative_point(geometry: dict) -> tuple[float, float]:
    """最大面積のポリゴンの重心を代表点にする。

    離島を多く持つ区域で、平均を取ると海上にピンが落ちるのを避けるため。
    """
    polygons: list[list[list[float]]] = []
    if geometry["type"] == "Polygon":
        polygons = [geometry["coordinates"][0]]
    elif geometry["type"] == "MultiPolygon":
        polygons = [poly[0] for poly in geometry["coordinates"]]

    best = (-1.0, 0.0, 0.0)
    for outer_ring in polygons:
        area, cx, cy = ring_area_and_centroid(outer_ring)
        if area > best[0]:
            best = (area, cx, cy)
    return round(best[2], 4), round(best[1], 4)  # (lat, lon)


def main() -> None:
    geojson = fetch_json(CLASS10_GEOJSON)
    points = {}
    for feature in geojson["features"]:
        props = feature["properties"]
        lat, lon = representative_point(feature["geometry"])
        points[props["code"]] = {
            "name": props.get("name", ""),
            "enName": props.get("enName", ""),
            "lat": lat,
            "lon": lon,
        }

    area = fetch_json(AREA_MASTER)
    names = {}
    for level in ("centers", "offices", "class10s", "class15s", "class20s"):
        for code, value in area.get(level, {}).items():
            names[code] = value.get("name", "")

    volcanoes = {}
    for item in fetch_json(VOLCANO_LIST):
        latlon = item.get("latlon") or []
        if len(latlon) != 2:
            continue
        volcanoes[item["code"]] = {
            "name": item.get("name_jp", ""),
            "enName": item.get("name_en", ""),
            "lat": float(latlon[0]),
            "lon": float(latlon[1]),
        }

    with io.open("assets/jma_volcano_points.json", "w", encoding="utf-8") as f:
        json.dump(volcanoes, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    with io.open("assets/jma_class10_points.json", "w", encoding="utf-8") as f:
        json.dump(points, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with io.open("assets/jma_area_names.json", "w", encoding="utf-8") as f:
        json.dump(names, f, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

    print(f"class10 points: {len(points)}")
    print(f"area names    : {len(names)}")
    print(f"volcanoes     : {len(volcanoes)}")


if __name__ == "__main__":
    main()
