# Ambient Screen Intelligence (v0.2)

ユーザーが見ている画面を AI も一緒に見て、**本当に価値があるときだけ**静かに補足情報を出す macOS メニューバーアプリです。

> 何を表示するかより、何を表示しないかを重視する。

v0.1 は「画面を継続監視し、変化した部分だけを解析して、外国語の文章に反応し、翻訳を HUD に表示する」ところまでを実装しています。

```
ScreenCaptureKit ─▶ FrameBuffer ─▶ ChangeDetector ─▶ AnalysisScheduler ─▶ OCR (変化領域のみ)
      ─▶ TextBlockGrouper ─▶ (ImageClassifier) ─▶ AIRouter (ignore-first) ─▶ Cooldown
      ─▶ TranslationProvider ─▶ HUD Overlay
```

## 必要環境

| 項目 | 要件 |
| --- | --- |
| macOS | 15.0 Sequoia 以降（macOS 26 推奨） |
| Xcode | 16.0 以降（Xcode 26 推奨） |
| CPU | Apple Silicon 推奨（Intel でも動作する想定） |
| 外部依存 | なし（Apple 純正 Framework のみ） |

使用 Framework: ScreenCaptureKit / Vision / NaturalLanguage / Translation / SwiftUI / AppKit / OSLog

## ビルド方法

### アプリ

1. `AmbientScreenIntelligence.xcodeproj` を Xcode で開く
2. Target `AmbientScreenIntelligence` → *Signing & Capabilities* で自分の **Team** を選ぶ（推奨）
   - Team なし（"Sign to Run Locally"）でもビルド・起動できますが、再ビルドのたびに署名が変わるため、画面収録の権限を再付与する必要が出ることがあります。
3. Scheme `AmbientScreenIntelligence` を選び ⌘R

コマンドラインの場合:

```sh
xcodebuild -project AmbientScreenIntelligence.xcodeproj \
  -scheme AmbientScreenIntelligence -configuration Debug build
```

### ユニットテスト

画面に依存しない純粋ロジック（`Sources/AmbientCore`）は Swift Package としてテストできます（macOS / Linux）。

```sh
swift test
```

## 起動方法

1. 起動するとメニューバーに 👁 アイコンが表示されます（Dock には表示されません）
2. 初回は画面収録の権限ダイアログが出ます（下記参照）
3. 権限付与後にアプリを再起動すると `Running` になり、解析が始まります
4. ブラウザで外国語（例: フランス語のニュース記事）を開くと、画面右上に翻訳 HUD が数秒表示されます

メニュー:

| 項目 | 動作 |
| --- | --- |
| Running / Paused until … | 現在の状態 |
| Pause 5 Minutes / Pause 30 Minutes | 一定時間キャプチャと解析を完全停止し、自動で再開 |
| Pause | 手動で再開するまで停止 |
| Resume | 再開 |
| Last: … / Not Useful | 直前の HUD を「役に立たない」と学習させ、似た表示を減らす |
| Stop Translating <言語> | 直前の HUD の言語を今後翻訳しない |
| Translation Languages… | 翻訳言語モデルの設定画面を開く |
| Settings… | 翻訳先言語、モード、除外アプリなど |
| Quit | 終了 |

デバッグログは Console.app でサブシステム `com.onishi.AmbientScreenIntelligence` を指定すると確認できます（`Capture started` / `Change detected` / `OCR started` / `Foreign language detected` / `Translated` / `HUD displayed` など）。OCR したテキスト本文はログに出しません。

## 必要な権限

### 画面収録（Screen Recording）

ScreenCaptureKit による画面取得に必須です。

1. 初回起動時のダイアログ、またはメニューの **Grant Screen Recording Permission…** から
   *システム設定 › プライバシーとセキュリティ › 画面収録とシステムオーディオ録音* を開く
2. `AmbientScreenIntelligence` をオンにする
3. アプリを再起動する（macOS の仕様で、権限は再起動後に有効になります）

macOS 15 以降は定期的に「画面収録を継続して許可しますか」という確認が表示されることがあります。

### 翻訳言語モデル

翻訳は Apple の Translation framework でオンデバイス実行します。アプリが勝手にモデルをダウンロードすることはないため、事前に
*システム設定 › 一般 › 言語と地域 › 翻訳言語* で使いたい言語（例: 英語・フランス語 → 日本語）をダウンロードしてください。
未インストールの言語ペアは翻訳されず、何も表示されません（ログに `languageNotInstalled` が記録されます）。

### Entitlements

| Entitlement | 理由 |
| --- | --- |
| `com.apple.security.app-sandbox` | サンドボックス化。ネットワーク・ファイルアクセスの Entitlement は **付与していません** |
| Hardened Runtime | 有効 |

画面収録は TCC（ユーザー許可）で管理されるため、追加の Entitlement は不要です。

## 実装済みの機能（v0.1）

- **メニューバー常駐アプリ**（`LSUIElement`、SwiftUI App + AppKit `NSStatusItem`）
- **Screen Capture**: `SCStream` でメインディスプレイを取得。自分自身の HUD と除外アプリのウィンドウはキャプチャ画像から除去
- **Frame Buffer**: `actor` で previous / current フレームを保持（previous は 320px のグレースケール縮小版のみ）
- **Change Detector**: 縮小グレースケール画像のセル単位差分。ノイズ・カーソル点滅・時計などの小さな変化は無視、近接領域は結合。動画やスクロールのように**変化し続ける領域は抑制**し、止まった瞬間に一度だけ解析
- **Analysis Scheduler**: 変化が落ち着いたら解析（最大 2 秒待ち）。OCR は最大 1fps（Balanced）。大きな変化がなければ OCR しない
- **OCR**: Vision `VNRecognizeTextRequest`（accurate、言語自動判定）を**変化領域だけ**に実行。折り返された行は段落にまとめる
- **言語判定**: NaturalLanguage `NLLanguageRecognizer`。短い文字列（`OK`, `Go`, `AI`, `Mac` など）、UI 定型句、URL・コード、ユーザーが読める言語は無視
- **翻訳**: `TranslationProvider` プロトコルで抽象化。実装は Apple Translation framework（macOS 26 は `TranslationSession` を直接生成、macOS 15 は `.translationTask` ブリッジ経由）
- **画像分類**: Vision `VNClassifyImageRequest` を大きな画像変化に低頻度で実行し、`person / animal / plant / food / landmark / text / unknown` にマッピング（v0.1 では表示には使わない）
- **AI Router（ignore-first）**: ルールベースの `InterestScorer` で 0.0〜1.0 のスコアを付け、0.7 以上のものだけ表示。メニューバー領域の文字やコーディングアプリでは減点
- **Cooldown**: 同じ内容は 5 分間再表示しない（OCR の揺れを吸収する正規化キー）
- **HUD**: 透明・最前面・クリック透過の `NSPanel` + SwiftUI。fade in 300ms → 3〜6 秒表示 → fade out 400ms。画面右上に表示
- **HUD の配置（v0.2）**: 対象テキストの近く（下 → 上 → 右 → 左の順で、文字を隠さず画面内に収まる位置）に表示。設定で右上固定にも切替可能
- **複数ディスプレイ（v0.2）**: 「マウスポインタのあるディスプレイを追従」をオンにすると、ポインタの移動に合わせてキャプチャ対象のディスプレイを切り替え（2 秒ごとに確認）。HUD はキャプチャ中のディスプレイに表示
- **Personalization（v0.2）**: HUD はクリック透過のまま、ポインタを 0.6 秒以上乗せると「関心あり」として加点し、乗せている間は消えない。メニューの *Not Useful* で減点。学習するのは「アクション × 言語 × アプリ」単位の重みだけで、テキストは保存しない（`PersonalizationModel`、上限 ±0.3）。設定画面からリセット可能
- **Pause / Resume**: 5 分・30 分・無期限。停止中はキャプチャ自体を止める
- **Privacy**: 除外アプリ（1Password などのパスワードマネージャー、メッセージ、写真）とパスワード系ウィンドウタイトルでは解析しない
- **Performance Mode**: Battery / Balanced / Performance（キャプチャ 5/15/30fps、Vision 0.5/1/2fps）
- **Unit Test**: ChangeDetector、AnalysisScheduler、ForeignTextDetector、AIRouter、InterestScore、Cooldown、TextBlockGrouper、PrivacyPolicy 、HUDPlacement、Personalization など 61 件

## プロジェクト構成

```
Sources/
├── AmbientCore/            プラットフォーム非依存の純粋ロジック（swift test 対象）
│   ├── Models/             ChangedRegion, RecognizedTextRegion, VisualCategory, AnalysisContext, RoutedAction, HUDMessage
│   ├── Capture/            GrayscaleFrame（BGRA → 縮小輝度）
│   ├── Vision/             ChangeDetector, AnalysisScheduler, TextBlockGrouper, VisualCategoryMapper
│   ├── Language/           ForeignTextDetector, TextHeuristics, CommonVocabulary, LanguageIdentifying
│   ├── Intelligence/       AIRouter, InterestScorer, InterestScore, CooldownCache, Personalization, AppContextClassifier
│   ├── Translation/        TranslationProvider
│   ├── Privacy/            PrivacyPolicy
│   ├── Presentation/       HUDPlacement
│   ├── Settings/           PerformanceMode
│   └── Future/             AnalysisResult, VisualMemory（将来用のプロトコル）
└── AmbientApp/             macOS アプリ（Xcode ターゲット）
    ├── App/                SwiftUI App, AppDelegate, AppController, AppSettings
    ├── Capture/            ScreenCaptureManager, FrameBuffer, FrameConverter
    ├── Vision/             OCRService, ImageClassifier, NLLanguageIdentifier
    ├── Intelligence/       AnalysisPipeline, AIProvider
    ├── Translation/        AppleTranslationProvider, TranslationBridge
    ├── Privacy/            PrivacyManager, ForegroundContextProvider
    ├── UI/                 OverlayWindowController, HUDView, MenuBarController, Settings
    └── Support/            Log (OSLog)
Tests/AmbientCoreTests/     ユニットテスト
Config/                     Info.plist, Entitlements
```

Xcode プロジェクトは Xcode 16 の「同期フォルダ」を使っているため、`Sources/AmbientCore` と `Sources/AmbientApp` にファイルを追加すると自動的にアプリターゲットに含まれます。

## 既知の制限

- 同時にキャプチャするディスプレイは 1 枚です（メイン、またはマウスポインタのあるディスプレイ）
- HUD の位置はキャプチャ時点の座標です。HUD 表示までにスクロールすると少しずれることがあります
- 翻訳には、事前に翻訳言語モデルのダウンロードが必要です
- macOS 15 の翻訳は SwiftUI `.translationTask` を 1×1 の透明ウィンドウでホストする方式のため、環境によっては動作しない可能性があります（8 秒でタイムアウトし、何も表示しません）。macOS 26 では直接 `TranslationSession` を使います
- 起動時点ですでに表示されている内容は解析しません（変化した部分だけが対象）
- 画像分類の結果はまだ表示に使っていません（ルーターは identify 系を表示閾値未満に抑えています）
- 除外アプリの「キャプチャ画像からの除去」は解析開始時点で起動中のアプリが対象です（後から起動したアプリも、前面にある間は解析しません）
- HUD はクリック透過なので「すぐ閉じる」という操作はありません。減点はメニューの *Not Useful* で行います
- 「検索した」（`searched`）フィードバックは型だけ用意しており、Web Search 実装時に接続します
- 開発環境の都合上、本リポジトリの初期実装は Linux 上でコアロジックのビルドとテストのみ検証しています。アプリ本体のビルドは GitHub Actions（macOS ランナー）で確認しています

## 今後の予定

- Visual Memory（timestamp / app / window title / URL / entities / summary / embedding）と Semantic Search（`VisualMemoryStore`）
- Web Search（person / animal / plant / landmark / product / news / technical term）
- Movie Mode（俳優、キャラクター、ロケ地、音楽）
- Coding Mode（VS Code / Terminal のコード説明、エラー解析）— `AppContextClassifier` で検出済み
- Foundation Models / Core ML によるローカル LLM 判定、`AIProvider` 経由の Cloud AI（オプトイン）
- Battery 状態に応じた自動モード切替

## Privacy policy（概要）

- **Local First**: OCR・言語判定・翻訳・画像分類はすべて Mac 上で実行します
- **保存しない**: 画面キャプチャはメモリ上でのみ扱い、ディスクに保存しません。前フレームは 320px の輝度サムネイルだけを保持します
- **送信しない**: アプリはサンドボックス化されており、ネットワークの Entitlement を持ちません。Cloud AI は未実装で、将来導入する場合も明示的なオプトインとします
- **除外**: パスワードマネージャー、メッセージ、写真などはキャプチャ画像から除去され、解析もされません。パスワード入力画面らしいウィンドウタイトルでも解析を止めます。除外アプリは設定画面で追加できます
- **ログ**: OCR したテキストの本文はログに記録しません（件数・文字数・言語コードのみ）
- **保存される設定**: 翻訳先言語・モード・除外アプリなどの設定値と、Personalization の重み（アクション・言語・アプリ ID ごとの数値のみ）を `UserDefaults` に保存します
