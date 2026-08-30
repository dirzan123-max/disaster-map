#!/usr/bin/env bash
# テスト用フィクスチャ（各 API の実際の応答）を取り直す。
#
# パーサのテストはネットワークに触らず、ここで保存したファイルだけを見る。
# API 側が仕様を変えたときは、これを実行し直すとテストが落ちて気づける。
#
#   bash tool/refresh_fixtures.sh
#
# 相手はいずれも無償公開の API。頻繁に叩かないこと。
set -euo pipefail

cd "$(dirname "$0")/.."
UA='disaster-map-build/0.1 (personal portfolio app)'

fetch() {
  echo "fetching $2"
  curl -sS -H "User-Agent: $UA" "$1" -o "test/fixtures/$2"
}

fetch 'https://api.p2pquake.net/v2/history?codes=551&codes=552&limit=30' p2p_history.json
fetch 'https://www.jma.go.jp/bosai/warning/data/warning/map.json' jma_warning_map.json

# 気象警報は防災情報XMLから取る。フィードと、その中の1件を保存する。
fetch 'https://www.data.jma.go.jp/developer/xml/feed/extra.xml' jma_warning_feed.xml
python - <<'PYX'
import io, re, urllib.request
feed = io.open('test/fixtures/jma_warning_feed.xml', encoding='utf-8').read()
url = None
for entry in re.findall(r'<entry>(.*?)</entry>', feed, re.S):
    title = re.search(r'<title>([^<]*)</title>', entry)
    if title and '気象特別警報・警報・注意報' in title.group(1):
        url = re.search(r'<id>([^<]*)</id>', entry).group(1)
        break
if url:
    print('fetching jma_warning_report.xml')
    request = urllib.request.Request(
        url, headers={'User-Agent': 'disaster-map-build/0.1 (personal portfolio app)'})
    with urllib.request.urlopen(request, timeout=30) as response:
        io.open('test/fixtures/jma_warning_report.xml', 'w', encoding='utf-8').write(
            response.read().decode('utf-8'))
PYX
fetch 'https://www.jma.go.jp/bosai/volcano/data/warning.json' jma_volcano_warning.json
fetch 'https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson' usgs_all_day.geojson

# 24時間より前を遡るための検索API。まとめフィードと同じ GeoJSON だが、
# 応答の形が変わっていないかを別に見張る（件数を絞って保存する）。
fetch 'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minmagnitude=5&limit=40&orderby=time' usgs_fdsn_query.geojson
fetch 'https://eonet.gsfc.nasa.gov/api/v3/events?category=wildfires&days=10&limit=40&status=open' eonet_events.json

# 気象庁の地震一覧は数千件あるため、先頭30件だけを保存する。
fetch 'https://www.jma.go.jp/bosai/quake/data/list.json' jma_quake_list.json
python - <<'PY'
import io, json
path = 'test/fixtures/jma_quake_list.json'
entries = json.load(io.open(path, encoding='utf-8'))
json.dump(entries[:30], io.open(path, 'w', encoding='utf-8'), ensure_ascii=False)
PY

echo 'done. run: flutter test'
