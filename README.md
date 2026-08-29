# 災害情報マップ

気象庁・USGS・NASA が公開している災害情報を取得し、**地図とお知らせで示す**アプリです。
Flutter の 1 コードベースから **Android アプリ**と **Web サイト**の両方を出しています。

**日本版 / 世界版**を切り替えると、データソース・地図タイル・表示言語がまとめて変わります。

> **本アプリは状況把握を助ける補助的なツールです。**
> 避難などの判断は、必ず自治体や気象庁の公式発表を優先してください。

---

## 何ができるか

| | 日本版 | 世界版 |
|---|---|---|
| 地震 | 気象庁の震度・震源（P2P地震情報 経由） | USGS |
| 津波 | 津波予報（予報区） | USGS の津波フラグ |
| 気象警報 | 大雨・暴風・洪水などの警報・注意報（一次細分区域ごと） | — |
| 噴火 | 噴火警報・噴火警戒レベル | NASA EONET の火山活動 |
| その他 | — | 山火事・洪水・暴風（NASA EONET） |

- 深刻度を **0〜4 の共通スケール**に揃えているので、種類の違う災害を同じ色・同じ基準で見比べられます
- **最終更新・取得失敗・キャッシュ表示**を常に画面に出します（いつの情報かが分からないのが災害時に一番困るため）
- 通信できないときは、最後に取得できた内容を「保存済み」と明示して表示します

## 通知

| | Android アプリ | Web 版 |
|---|---|---|
| 端末通知 | 15分ごとに自動確認し、条件に合えば通知 | ブラウザには仕組みが無いため、**画面上に通知の見本**を表示 |
| 業務チャット連携 | Slack / Teams / Discord へ送信 | 送信内容（curl）を提示 |
| サーバー不要の定期監視 | — | `.github/workflows/watch.yml`（GitHub Actions の cron） |

通知するかどうかの判定（`NotificationSettings.matches`）は、端末通知・Webhook・Web版のプレビューで**同じものを使っています**。
画面に見えている条件と、実際に飛ぶ通知が食い違わないようにするためです。

---

## 費用がかからない構成

**サーバーを一切持ちません。** 使っている API はすべて `Access-Control-Allow-Origin: *` を返すため、
ブラウザやアプリから直接取得できます。中継サーバーが要らないので、運用費がゼロになります。

| 用途 | 取得先 | 費用 |
|---|---|---|
| 地震・津波（日本） | `api.p2pquake.net`（気象庁発表の配信） | 無料・キー不要 |
| 気象警報（日本） | `jma.go.jp/bosai/warning/data/warning/map.json` | 無料・キー不要 |
| 噴火警報（日本） | `jma.go.jp/bosai/volcano/data/warning.json` | 無料・キー不要 |
| 地震（世界） | `earthquake.usgs.gov` | 無料・キー不要 |
| 火山・山火事・洪水（世界） | `eonet.gsfc.nasa.gov` | 無料・キー不要 |
| 地図（日本） | 地理院タイル | 無料（出典表示が条件） |
| 地図（世界） | OpenStreetMap | 無料（出典表示が条件） |
| Web の公開 | GitHub Pages | 無料 |
| 定期監視 | GitHub Actions | 無料（Public リポジトリ） |

外部の無償 API に頼っているため、**呼び出し間隔を空ける・User-Agent を名乗る**ことを実装側の約束にしています（`lib/core/app_http.dart`）。

---

## 動かす

```bash
flutter pub get

flutter run -d chrome        # Web
flutter run -d <端末ID>       # Android 実機

flutter test                 # パーサのテスト（外部 API に触らない）
```

### 配布物を作る

```bash
flutter build web --release --base-href "/disaster_map/"
flutter build apk --release --split-per-abi   # 端末に配るのはこちら（arm64 版で約22MB）
```

`--split-per-abi` を付けないと 3 種類の CPU 向けが 1 つに入り、55MB になります。

---

## 構成

```
lib/
  core/        通信・地域・時刻・座標形式の共通処理
  domain/      DisasterEvent / EventKind / Severity（全ソース共通のモデル）
  data/
    sources/   API ごとの取得と正規化（6本）
    disaster_repository.dart   地域に応じて束ね、失敗を吸収し、キャッシュする
  features/    地図・一覧・詳細・設定・通知
assets/        気象庁の区域・火山の代表点、日本語フォント
tool/          アセット生成、フィクスチャ更新、定期監視スクリプト
```

設計の考え方は [docs/architecture.md](docs/architecture.md) に書いています。

### アセットの再生成

気象庁の警報・噴火警報は**座標を持たない**（区域名・火山名だけ）ため、
公式の区域ポリゴンから代表点を計算してアプリに同梱しています。

```bash
python tool/build_assets.py    # 区域143件・火山117件の代表点を生成
bash tool/fetch_font.sh        # 日本語フォント（Noto Sans JP）を取得
bash tool/refresh_fixtures.sh  # テスト用に各 API の応答を保存し直す
```

---

## 出典・ライセンス

- 気象庁（地震・津波・気象警報・噴火警報） https://www.jma.go.jp/bosai/
- P2P地震情報（気象庁発表の配信） https://www.p2pquake.net/
- USGS Earthquake Hazards Program https://earthquake.usgs.gov/
- NASA EONET https://eonet.gsfc.nasa.gov/
- 地理院タイル（国土地理院） https://maps.gsi.go.jp/development/ichiran.html
- © OpenStreetMap contributors https://www.openstreetmap.org/copyright
- Noto Sans JP（SIL Open Font License 1.1）

取得先はいずれも公共機関またはボランティアが運営する無償の公開データです。
利用にあたっては、各提供元が示す条件を確認してください。
