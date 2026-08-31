# 災害情報マップ

気象庁・USGS・NASA が公開している災害情報を集めて、**1つの地図と通知**で示すアプリです。
Flutter の1コードベースから **Android・Windows・Web** の3つを出しています。

**▶ ブラウザで試す: https://dirzan123-max.github.io/disaster-map/**
（インストール不要。ただし通知は Android / Windows 版のみ）

> **状況把握を助ける補助的なツールです。**
> 避難などの判断は、必ず自治体や気象庁の公式発表を優先してください。
> 緊急地震速報（揺れる前に鳴るもの）は扱えません（[理由](#リアルタイム監視)）。

---

## 目次

- [何ができるか](#何ができるか)
- [動かす](#動かす)
- [配る](#配る)
- [画面の作り](#画面の作り)
- [設計の要点](#設計の要点)
- [データソース](#データソース)
- [通知の仕組み](#通知の仕組み)
- [対応環境と、できないこと](#対応環境とできないこと)
- [ソースの構成](#ソースの構成)
- [使っているもの](#使っているもの)
- [テスト](#テスト)
- [同梱データの作り直し](#同梱データの作り直し)
- [踏んだ地雷](#踏んだ地雷)
- [引き継ぐ人へ](#引き継ぐ人へ)

---

## 何ができるか

**1つの地図**に、日本国内は気象庁、国外は USGS と NASA の情報を自動で使い分けて出します。
地域を切り替える操作は要りません。

| 種類 | 情報源 | 取得できる範囲 |
|---|---|---|
| 地震 | 国内: 気象庁（震度つき）／国外: USGS | 全世界・30日。国外は M4.5 以上 |
| 津波 | 気象庁の津波予報 | 日本のみ |
| 気象警報 | 気象庁 防災情報XML | 日本のみ。今発表中のもの |
| 火山 | 国内: 噴火警報／国外: NASA EONET | 全世界・1年 |
| 山火事 | NASA EONET（IRWIN） | **米国のみ**・10日 |
| 暴風・台風 | NASA EONET（JTWC 等） | 全世界・14日 |
| 洪水 | NASA EONET | 全世界・60日（登録は少ない） |

**取れていない範囲は地図をグレーで塗ります。**
「気象警報」を選ぶと日本以外が、「山火事」を選ぶと米国以外が灰色に沈みます。
これが無いと「気象警報は日本でしか起きていない」と誤解させてしまうためです。

そのほか:

- 深刻度を **0〜4 の共通スケール**に揃え、種類の違う災害を同じ色・同じ基準で見比べられます
- **災害の種類 / 深刻度 / 期間 / 国**で絞り込めます。選んだ条件は次に開いたときも残ります
- **最終更新・取得失敗・キャッシュ表示**を常に画面に出します（いつの情報か分からないのが災害時に一番困るため）
- 通信できないときは、最後に取得できた内容を「保存済み」と明示して表示します
- 英語で配信される情報は**アプリ内で日本語に直します**（地名は原文のまま残し、詳細に併記）

---

## 動かす

### はじめに一度だけ

| | 必要なもの |
|---|---|
| 共通 | [Flutter SDK](https://docs.flutter.dev/get-started/install)（stable / 開発時は 3.44.8） |
| Android | Android Studio または Android SDK（`flutter doctor` が案内します） |
| Windows | Visual Studio Build Tools（下記） |
| Web | Chrome |

```bash
flutter doctor      # 足りないものを教えてくれる
flutter pub get     # パッケージの取得
```

Windows 版をビルドするなら、C++ ツールを入れます（**ATL を忘れずに**）。

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools --override `
  "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.ATL --includeRecommended"
```

`Microsoft.VisualStudio.Component.VC.ATL` が無いと、通知プラグインのビルドが
`atlbase.h が見つからない`（error C1083）で止まります。

### 開発中に動かす

```bash
flutter run                 # つないでいる Android 端末
flutter run -d chrome       # ブラウザ
flutter run -d windows      # パソコン
flutter devices             # 何が使えるか一覧
```

### 直す前と後にやること

```bash
flutter analyze && flutter test
```

CI でも同じものが走ります。落ちたまま push すると GitHub 上で赤くなります。

---

## 配る

### Android

```bash
flutter build apk --release --build-number 2019
#  → build/app/outputs/flutter-apk/app-release.apk
```

**`--build-number` は毎回1つ上げます。** Android は versionCode が
今入っているものより小さいと上書きを拒否し、`INSTALL_FAILED_VERSION_DOWNGRADE`
になります。今どれが入っているかは次で分かります。

```bash
adb -s <端末ID> shell "dumpsys package com.yjfuj.disaster_map | grep -m1 versionCode"
```

端末に入れる:

```bash
adb devices                                   # 端末IDを確認
adb -s <端末ID> install -r <APKのパス>         # -r は上書き更新
```

> `-s <端末ID>` は必ず付けてください。省くと**接続順で選ばれた端末**に入り、
> エミュレータのつもりで実機を上書きすることがあります。

ケーブルを抜いて Wi-Fi で入れたいときは、一度だけ USB でつないで切り替えます。

```bash
adb -s <端末ID> tcpip 5555
adb -s <端末ID> shell "ip -f inet addr show wlan0 | grep -oE 'inet [0-9.]+'"
adb connect <出てきたIP>:5555                 # 以降はケーブル不要
```

release ビルドは debug キーで署名しています（[引き継ぐ人へ](#引き継ぐ人へ) 参照）。

### Windows

```bash
flutter build windows --release
#  → build/windows/x64/runner/Release/  （exe + DLL + data、約37MB）
```

**単体の exe にはなりません。** `disaster_map.exe` は 91KB しかなく、
同じフォルダの DLL と `data/` が揃っていないと動きません。配るときは
**フォルダごと** ZIP に固めます。

```powershell
Compress-Archive -Path "build/windows/x64/runner/Release/*" -DestinationPath disaster-map-windows.zip
```

未署名なので、受け取った側では SmartScreen の警告
（「WindowsによってPCが保護されました」）が出ます。
消すにはコード署名証明書が要ります。

### Web

`main` に push するだけです。GitHub Actions がビルドして GitHub Pages へ配信します
（`.github/workflows/pages.yml`）。

```bash
git push        # → https://dirzan123-max.github.io/disaster-map/
```

手元で確認したいときは:

```bash
flutter build web --release
cd build/web && python -m http.server 8000
```

> `flutter build web` の出力は `--base-href` の指定に依存します。
> ローカル確認では既定（`/`）、Pages ではリポジトリ名のサブパスになるため、
> CI 側で `--base-href "/disaster-map/"` を渡しています。

---

## 画面の作り

```
┌─────────────────────────────┐
│ 災害情報マップ        🔄 ⚙  │  更新 / 設定
├─────────────────────────────┤
│ [地震][気象警報][火山][山火事] │  種類（1つだけ選ぶ）
│ [深刻度: 軽微以上][期間: …]   │  絞り込み
├─────────────────────────────┤
│ 最終更新 3分前 ・ 232件       │  鮮度・件数・取得失敗
├─────────────────────────────┤
│                             │
│          地   図             │  ピン（色=深刻度、絵=種類）
│                             │  情報源が無い範囲はグレー
│  ───────────────  ← つまみ   │
│  一覧（新しい順）・232件      │  引き上げると一覧
└─────────────────────────────┘
```

初めて開いたときは3枚の案内が出ます（スキップ可）。
詳しい説明とデータ範囲の表は、設定 → 「使い方とデータの範囲」にあります。

---

## 設計の要点

### 1. 全部の情報源を1つのモデルへ正規化する

`DisasterEvent` に寄せています。地図・一覧・通知・Webhook は、元の API の形を一切知りません。
新しい取得先を足す作業が「`DisasterSource` を1つ書く」だけで済みます。

```
JMA / P2P / USGS / EONET  →  各 Source  →  DisasterEvent  →  地図・一覧・通知
```

### 2. 深刻度は 0〜4 の共通スケールに写像する

震度・マグニチュード・警報の種類・噴火警戒レベルは、そのままでは比較できません。

| | 日本 | 世界 |
|---|---|---|
| 4 重大 | 特別警報 / 震度6弱以上 / 大津波警報 | M7.0以上 |
| 3 警戒 | 警報 / 震度5弱・5強 / 津波警報 | M6.0以上 |
| 2 注意 | 注意報 / 震度3・4 / 津波注意報 | M4.5以上 |
| 1 軽微 | 震度1・2 | M4.5未満 |

**この表がアプリ内の唯一の基準**で、地図の色・凡例・通知しきい値がすべてこれを見ます。

### 3. 地図は1つ

もとは「日本版 / 世界版」を切り替える形でしたが、これは情報源の都合であって
利用者の関心ではありません。切り替えを残した結果
「世界版に日本の地震は出るのか」が種類によって変わり、説明できなくなりました。

いまは1つの地図にして、情報源はアプリが自動で使い分けます。
日本国内の地震・火山が両方から来たときは、詳しい気象庁のほうを残します。

### 4. 座標を持たない情報を捨てない

気象庁の警報は「区域」、噴火警報は「火山」単位で発表され、**応答に座標がありません**。
公式データから代表点を計算してアプリに同梱しています
（一次細分区域143件・火山117件・国境239件）。

津波予報のように代表点が手に入らないものは地図に出せませんが、
**一覧には必ず出し**、「地図に出せない情報 ◯件」と件数も示します。
地図に出せないことを、情報を捨てる理由にはしていません。

### 5. サーバーを持たない

中継サーバーを立てれば CORS も認証もレート制限も自由に扱えますが、
個人で続けるには運用費と手間が重い。そこで **CORS が許可されている取得先だけを選びました**
（実際に `Origin` を付けて応答ヘッダを確認しています）。

通知も「端末が自分で取りに行き、自分で鳴らす」方式です。

---

## データソース

| 情報 | 取得先 | 備考 |
|---|---|---|
| 地震（国内） | P2P地震情報 `api.p2pquake.net` | 気象庁発表の配信。直近100件（約1週間） |
| 地震（国内・代替） | 気象庁 `bosai/quake/data/list.json` | P2P が落ちたときだけ |
| 地震（国外） | USGS まとめフィード ＋ 検索API（FDSN） | 直近24時間は全件、30日は M4.5 以上 |
| 気象警報 | 気象庁 防災情報XML `developer/xml/feed/extra.xml` | 発表ごとの時刻が入っている |
| 噴火警報 | 気象庁 `bosai/volcano/data/warning.json` | 今の噴火警戒レベル |
| 世界の自然災害 | NASA EONET v3 | 山火事・台風・火山・洪水 |
| 地図タイル | OpenStreetMap | 出典表示が利用条件 |
| 国境 | Natural Earth（同梱） | 国の判定と国名の和訳 |

いずれも**鍵も申請も不要**で、CORS が許可されています。

<details>
<summary>採用しなかったもの</summary>

| | 理由 |
|---|---|
| ReliefWeb API | appname の事前申請が必要 |
| GDACS | エンドポイントによって CORS の扱いが不安定 |
| CARTO のベースマップ | API キーが必要になり、地図に透かしが入る |
| 地理院タイル | 国内は美しいが**国外が真っ白**。1枚で世界を見せる構成では使えない |
| FCM によるプッシュ通知 | 送信側にサーバーが要る |
| NASA FIRMS（山火事を全世界に） | API キーの登録が必要（検討の余地あり） |

</details>

---

## 通知の仕組み

**種類ごとに深刻度を決めます。**「地震は警戒以上、津波は注意から」のように、
種類で重さが違うためです。「通知しない」も同じ並びから選べます。

判定は `NotificationSettings` 1か所に集約し、
画面の絞り込み・端末通知・Webhook・Web版のプレビューがすべて共有します。
「画面に見えている条件」と「実際に飛ぶ通知」が必ず一致します。

### 3つの経路

| 経路 | 環境 | 遅れ |
|---|---|---|
| 定期取得（WorkManager） | Android | 最大15分 |
| 常駐監視（WebSocket + フォアグラウンドサービス） | Android | **数秒** |
| アプリ内監視（タイマー + WebSocket） | Windows | 5分 / **数秒** |

どの経路も `EventNotifier` を通します。判定と「二重に鳴らさない」記録
（`SeenStore`）を共通にしないと、条件がずれて「片方だけ鳴る」ためです。

### リアルタイム監視

P2P地震情報が WebSocket を公開しているので、つなぎっぱなしにして
発表が流れてきた瞬間に通知します。**サーバーを持たずに秒単位**にできます。

Android では常駐サービスが必要で、通知バーに居座り電池も食うため、既定では切ってあります。
パソコンでは常駐サービスが要らないので、そのままつなぐだけです。

> **緊急地震速報は扱えません。** あれは気象庁から携帯網を通って端末の OS 機能
> （エリアメール／ETWS）へ直接届くもので、アプリからは触れません。
> ここで速くなるのは「地震が起きた**後**の発表」です。

### 業務チャットへの連携

Slack / Microsoft Teams / Discord の Incoming Webhook に対応しています。
対策本部のチャンネルに履歴として残したい場合に使います。

---

## 対応環境と、できないこと

| | Android | Windows | Web |
|---|---|---|---|
| 地図・一覧・絞り込み | ○ | ○ | ○ |
| 端末通知 | ○ | ○ | **×** ブラウザ用の実装が無い |
| 自動確認 | 15分ごと | 5分ごと（開いている間） | **×** |
| リアルタイム監視 | ○（常駐サービス） | ○（つなぐだけ） | **×** |
| Webhook 送信 | ○ | ○ | **×** 送信先が CORS 非対応 |

**Web版は「開いて状況を見る」ためのもの**で、「閉じていても気づく」ことはできません。
その代わり画面内に通知の見本を出し、Webhook はそのまま実行できる `curl` を提示します。

---

## ソースの構成

```
lib/
├── core/            共通の道具（HTTP・時刻整形・座標・和訳辞書）
├── domain/          モデル（DisasterEvent / EventKind / Severity / TimeWindow）
├── data/
│   ├── sources/     取得先ごとの Source（1ファイル1API）
│   ├── disaster_repository.dart   全ソースの取得・重複排除・国の判定
│   ├── coverage.dart              どこまで取れているか
│   ├── country_index.dart         国境と国名（同梱データ）
│   └── event_cache.dart           前回の内容
└── features/
    ├── app_state.dart   画面全体の状態（ChangeNotifier）
    ├── map/             地図
    ├── list/ detail/    一覧と詳細
    ├── notify/          通知の3経路 + Webhook
    ├── settings/        設定と国の選択
    └── tutorial/        初回案内と使い方
```

状態管理は `ChangeNotifier` + `ListenableBuilder` だけで、状態管理ライブラリを入れていません。
状態が「取得結果」と「絞り込み」の2つしかなく、導入する利点より読む負担のほうが大きいためです。

---

## 使っているもの

| | 用途 |
|---|---|
| `flutter_map` | 地図（Google Maps と違い API キーが不要） |
| `http` | 取得 |
| `xml` | 気象庁 防災情報XML の解析 |
| `web_socket_channel` | リアルタイム監視 |
| `shared_preferences` | 設定とキャッシュ |
| `flutter_local_notifications` | 端末通知（Android / Windows） |
| `workmanager` | 15分ごとの定期実行（Android） |
| `flutter_foreground_task` | 常駐監視（Android） |
| `intl` / `url_launcher` | 時刻の整形 / 出典を開く |

---

## テスト

```bash
flutter test      # 98件
flutter analyze
```

各 API の**実際の応答を `test/fixtures/` に保存**し、パーサはそれに対してテストします。
ネットワークが要らないので CI で安定して回り、
`tool/refresh_fixtures.sh` で取り直したときに**仕様変更があればテストが落ちます**。

特に落としたくない間違いを名指しでテストしています。

- GeoJSON の `[経度, 緯度]` を取り違えていないか
- 日本時間を UTC に直しているか（9時間ずれ）
- 気象庁の続報が並んでいるとき、同じ地震を重複させていないか
- 区域コードから座標を引けているか（引けないと地図から消える）
- 地図の縮小の下限（世界地図が2枚見えないか）
- 通知の条件を保存して読み直しても変わらないか

---

## 同梱データの作り直し

滅多に変わらないデータは、実行時に取得せずアプリに同梱しています。

```bash
python tool/build_assets.py      # 気象庁の区域・火山の代表点
python tool/build_countries.py   # Natural Earth の国境（239件）
bash tool/refresh_fixtures.sh    # テスト用フィクスチャの取り直し
```

---

## 踏んだ地雷

実際に詰まって直したものです。詳しい経緯は [`docs/architecture.md`](docs/architecture.md) にあります。

| 症状 | 原因 |
|---|---|
| Web の初回表示が豆腐（□）になり、ラベルが途中で欠ける | 日本語フォント未同梱。文字幅の計算までずれる |
| 拡大しようとすると地図が回る | flutter_map は既定で2本指の回転を受け付ける |
| 世界地図が2枚並んで見える | 縮小の下限だけでは足りず、動かせる範囲の制限も要る |
| 日本中心の世界地図が作れない | 繰り返し描画を切ったのが誤り。繰り返しは残し、動かせる窓を1周分に限る |
| グレーの塗りが反転する | flutter_map の穴あきポリゴンは穴の側が塗られる |
| 期間を変えても件数が変わらない | 「継続中だから対象外」にしていた。EONET は開始時刻を持っている |
| 気象警報が3か月前のまま | 気象庁 bosai の警報 API が停止。防災情報XMLへ切り替え |
| 台湾が中国と同じ扱いになる | Natural Earth の ISO_A2 が `CN-TW` |
| CORS 非対応だと誤判定 | `Origin` ヘッダを付けずに応答ヘッダを見ていた |
| テストが無限に止まる | 画面のない場所からネイティブのサービスを呼んでいた |

---

## 引き継ぐ人へ

`git clone` して `flutter pub get` → `flutter run` で動きます。
同梱データ（フォント・国境・気象庁の代表点）も `pubspec.lock` もコミット済みなので、
`tool/*.py` を走らせ直す必要はありません。

詰まりやすいのは次の4点です。

### 1. Windows ビルドには ATL が要る

`Microsoft.VisualStudio.Component.VC.ATL` を入れていないと、
通知プラグインのビルドが `atlbase.h が見つからない` で止まります
（[インストール手順](#動かす)）。

### 2. Android の署名は debug キーのまま

```kotlin
// android/app/build.gradle.kts
signingConfig = signingConfigs.getByName("debug")
```

debug キーは**開発機ごとに違う**ため、別の人がビルドした APK は署名が変わります。
すでに入っている端末には上書き更新できず、一度アンインストールが必要です。

Google Play へ出すときは専用のキーストアに差し替えてください。
**キーストアを失うと同じアプリとして更新できなくなります。**

### 3. 定期監視の Webhook はリポジトリの secret

`.github/workflows/watch.yml` は `secrets.WEBHOOK_URL` を使います。
fork / clone した場合は自分で設定してください（無くても他はすべて動きます）。

### 4. Flutter のバージョンは固定していない

CI は `channel: stable` を使っています。パッケージは `pubspec.lock` で固定されますが、
Flutter 本体は将来の stable に追随します。壊れたら
`subosito/flutter-action` の `flutter-version` を指定して固定してください
（開発時の確認は Flutter 3.44.8 / Dart SDK ^3.12.2）。

### 変更したら

```bash
flutter analyze && flutter test    # push 前に。CI でも同じものが走る
```

実装を変えたときは [`docs/architecture.md`](docs/architecture.md) の
該当箇所も同じ作業の中で直してください。
「なぜそうしたか」が残っていないと、同じ地雷を踏み直すことになります。

---

## 出典

- 気象庁（地震・津波・気象警報・噴火警報）
- P2P地震情報（気象庁発表の配信）
- USGS Earthquake Hazards Program
- NASA EONET
- © OpenStreetMap contributors
- Natural Earth（国境データ・パブリックドメイン）
- Noto Sans JP（SIL Open Font License 1.1）
