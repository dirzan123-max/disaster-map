#!/usr/bin/env bash
# 同梱する日本語フォントを取得する。
#
#   bash tool/fetch_font.sh
#
# なぜ同梱するのか:
#   Flutter Web は日本語の予備フォントを表示の直前に取りに行く。
#   同梱しないと初回表示が豆腐（□）になるうえ、文字幅の計算が実際の描画と
#   ずれて、チップやボタンのラベルが途中で欠ける。
#
# ライセンス:
#   Noto Sans JP は SIL Open Font License 1.1。同梱・再配布が認められている。
#   https://github.com/notofonts/noto-cjk
#
# 大きさを削りたくなったら:
#   pip install fonttools したうえで pyftsubset を使い、実際に使う文字だけに
#   絞ると 4.5MB から数百KBまで落とせる。ただし地名は動的に増えるため、
#   常用漢字＋人名用漢字の範囲は残すこと。
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p assets/fonts

URL='https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf'
curl -sSL "$URL" -o assets/fonts/NotoSansJP-Regular.otf

# OpenType(CFF) は "OTTO" で始まる。壊れたファイルを掴んでいないか確かめる。
head -c 4 assets/fonts/NotoSansJP-Regular.otf | grep -q 'OTTO' \
  || { echo 'ダウンロードしたファイルがフォントではありません'; exit 1; }

ls -l assets/fonts/NotoSansJP-Regular.otf
