# Ambient Screen Intelligence (v0.11)

ユーザーが見ている画面を AI も一緒に見て、**本当に価値があるときだけ**静かに補足情報を出す macOS メニューバーアプリです。翻訳・専門用語・エラーの原因・換算・要約などを**すべて Mac の中で**行い、アプリは通信しません（ローカル専用）。

> 何を表示するかより、何を表示しないかを重視する。

使い方は **[docs/MANUAL.md](docs/MANUAL.md)**（利用者向けマニュアル）を見てください。

## ドキュメント

| 文書 | 内容 | 主な読者 |
| --- | --- | --- |
| [docs/MANUAL.md](docs/MANUAL.md) | かんたんマニュアル（使い方・設定・プライバシー・困ったとき） | 利用者 |
| [docs/SPEC.md](docs/SPEC.md) | 製品仕様（要件 ID と実装状況の正本） | 開発 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 技術構成・ローカル AI の方針・データ・プライバシー設計 | 開発 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 現在地・次にやること・アイデアのバックログ・判断事項・リスク | 開発 |
| [docs/CHECKLIST.md](docs/CHECKLIST.md) | 実機検証チェックリスト（結果は `docs/perf/`） | 開発・検証 |
| [docs/RELEASE.md](docs/RELEASE.md) | 署名・公証・DMG の作り方 | 配布 |
| [CLAUDE.md](CLAUDE.md) | 開発ルール（Claude Code / Codex 向けの指示を含む） | 開発 |

```
ScreenCaptureKit ─▶ ChangeDetector ─▶ OCR / 画像分類（変化領域のみ）
   ─▶ ルール ─▶ Apple のオンデバイス ML ─▶ オンデバイス LLM（必要なときだけ）
   ─▶ 機能の設定と優先順位 ─▶ HUD ─▶ Archive（SQLite、この Mac の中だけ）
```

## 必要環境

| 項目 | 要件 |
| --- | --- |
| macOS | 15.0 Sequoia 以降（Foundation Models を使う機能は macOS 26 ＋ Apple Intelligence） |
| Xcode | 16.0 以降（Xcode 26 推奨） |
| CPU | Apple Silicon 推奨 |
| 外部依存 | GRDB 7（SQLite）のみ。ほかは Apple 純正 Framework |

使用 Framework: ScreenCaptureKit / Vision / NaturalLanguage / Translation / Foundation Models / CoreServices（辞書）/ SwiftUI / AppKit / OSLog

## ビルドとテスト

1. `AmbientScreenIntelligence.xcodeproj` を Xcode で開く
2. Target `AmbientScreenIntelligence` → *Signing & Capabilities* で自分の **Team** を選ぶ（推奨。Team なしでも動くが、再ビルドのたびに画面収録の権限の再付与が必要になることがある）
3. Scheme `AmbientScreenIntelligence` を選び ⌘R

```sh
# アプリ
xcodebuild -project AmbientScreenIntelligence.xcodeproj -scheme AmbientScreenIntelligence -configuration Debug build
# 純粋ロジックのテスト（macOS / Linux。ストアのテストは macOS のみ）
swift test
```

CI（`.github/workflows/ci.yml`）は Linux でコアのテスト、macOS 15 / 26 でアプリのビルドとテストを行います。デバッグログは Console.app でサブシステム `com.onishi.AmbientScreenIntelligence`（認識テキストの本文は出しません）。

## 権限と Entitlements

| 項目 | 理由 |
| --- | --- |
| 画面収録（TCC） | 画面の取得。初回起動ガイドから許可し、アプリを再起動 |
| `com.apple.security.app-sandbox` | サンドボックス化。ファイル・**ネットワーク**の Entitlement は持たない（v0.11 で `network.client` を削除） |
| `com.apple.security.automation.apple-events`（＋対象ブラウザの temporary exception） | 前面タブの URL を読むため。macOS がブラウザごとに許可を求め、設定でオフにできる |
| Hardened Runtime | 有効 |

⌥ ＋ 丸のジェスチャはポインタと修飾キーの状態を CoreGraphics で読むだけで、入力監視・アクセシビリティの権限は不要の見込みです（実機で確認中）。

## プライバシー（概要）

画面の画像は保存せず、アプリは通信しません。記録するのは HUD に出した内容、（オンの場合）ページのタイトル・URL（クエリなし）・閲覧時間、（オンの場合）AI の回答だけで、この Mac の中（バックアップ対象外）に保存し、いつでも消せます。秘密情報を含む文は翻訳・説明・記録・AI への入力に使いません。ログに認識テキストを出しません。詳しくは [docs/MANUAL.md](docs/MANUAL.md) §8 と [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §6。

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
│   ├── Memory/             VisualMemoryEntry, VisualMemoryIndex, MemoryQueryParser
│   ├── LocalAI/            端末内の識別の方針、略語の用語集、単位換算
│   ├── Interaction/        丸で囲むジェスチャの判定、囲んだ範囲に何を出すか
│   ├── Context/, Coding/, Knowledge/, Media/, Security/  各機能の判定ロジック
│   └── Future/             AnalysisResult
├── AmbientStore/           SQLite（GRDB）の保存層、macOS の swift test 対象
└── AmbientApp/             macOS アプリ（Xcode ターゲット）
    ├── App/                SwiftUI App, AppDelegate, AppController, AppSettings
    ├── Capture/            ScreenCaptureManager, FrameBuffer, FrameConverter
    ├── Vision/             OCRService, ImageClassifier, NLLanguageIdentifier
    ├── Intelligence/       AnalysisPipeline, AppleIntelligenceReasoner, LocalKnowledgeReasoner, AIProvider
    ├── Translation/        AppleTranslationProvider, TranslationBridge
    ├── Privacy/            PrivacyManager, ForegroundContextProvider
    ├── Context/            閲覧記録、作品・ニュースの補足
    ├── Interaction/        ⌥＋丸のポインタ監視
    ├── UI/                 HUD、Archive、Settings、初回起動ガイド
    └── Support/            Log (OSLog)
Tests/AmbientCoreTests/     ユニットテスト
Tests/AmbientStoreTests/    SQLite 保存層のテスト（macOS）
Config/                     Info.plist, Entitlements
```

Xcode プロジェクトは Xcode 16 の「同期フォルダ」を使っているため、`Sources/AmbientCore`・`Sources/AmbientStore`・`Sources/AmbientApp` にファイルを追加すると自動的にアプリターゲットに含まれます。

## 既知の制限

- 同時にキャプチャするディスプレイは 1 枚です（メイン、またはマウスポインタのあるディスプレイ）
- ローカライズは日本語と英語のみです。HUD に出る翻訳・解説の本文は設定の「翻訳先」の言語で、カードの演出文字（コードネーム・`INTEL` など）は英語です
- 配布用の署名・公証は判断事項 D-6 の決定と Developer ID 証明書が必要です（現在の CI ビルドは未署名）
- HUD の位置はキャプチャ時点の座標です。HUD 表示までにスクロールすると少しずれることがあります
- macOS 15 の翻訳は SwiftUI `.translationTask` を 1×1 の透明ウィンドウでホストする方式のため、環境によっては動作しない可能性があります（8 秒でタイムアウトし、何も表示しません）。macOS 26 では直接 `TranslationSession` を使います
- 起動時点ですでに表示されている内容は解析しません（変化した部分だけが対象）
- 端末内の LLM は画像を見られず、知識も学習時点までです。識別・公人・作品・ニュースの補足は分類ラベルと画面上の文字からの推定で、外れることがあります（新しい作品・最近のニュースは分かりません）。Apple Intelligence（macOS 26）が無い Mac では、これらは表示されません
- 除外アプリの「キャプチャ画像からの除去」は解析開始時点で起動中のアプリが対象です（後から起動したアプリも、前面にある間は解析しません）
- 略語の用語集はメモリ上だけにあり、アプリを終了すると消えます
- 開発環境の都合上、本リポジトリの初期実装は Linux 上でコアロジックのビルドとテストのみ検証しています。アプリ本体のビルドは GitHub Actions（macOS ランナー）で確認しています
