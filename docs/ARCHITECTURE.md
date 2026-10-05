# 技術構成・データ設計・プライバシー設計

要件は [SPEC.md](SPEC.md)、実装状況と残作業は [ROADMAP.md](ROADMAP.md)。本書は v0.10 の実装を説明し、未実装の構想は「将来案」と明記する。アプリの実機動作と性能目標は未検証。

---

## 1. 技術スタック

| 層 | 採用 | 備考 |
| --- | --- | --- |
| 言語 / UI | Swift 5 モード、SwiftUI ＋ AppKit | Swift Concurrency（actor / async） |
| 画面取得 | ScreenCaptureKit (`SCStream`) | BGRA、IOSurface のままメモリで処理 |
| 画像解析 | Vision（OCR・画像分類）、Core ML（将来） | |
| 言語 | NaturalLanguage（言語判定・文埋め込み・固有名詞抽出） | |
| 翻訳 | Translation framework | macOS 26 は `TranslationSession` 直接、15 は SwiftUI ブリッジ |
| ローカル LLM | Foundation Models（macOS 26 + Apple Intelligence） | BRIEF、用語・エラー・コードの説明、判断が割れる候補の判定、セッション名 |
| 永続化 | SQLite（GRDB 7、ROADMAP D-1 で決定） | `Sources/AmbientStore`。Linux 非対応のためテストは macOS CI |
| ベクトル検索 | SQLite から候補を最大 2,000 件取得し、埋め込みの類似度などで再順位付け | 大規模化した場合の索引は将来案 |
| クラウド AI | `GeminiProvider` と `NetworkGate` | 設定で有効化し、API キーがある場合のみ。Battery モードでは通信しない |
| CI | GitHub Actions: Linux でコアのテスト、macOS 15 / 26 でアプリのビルドとテスト | |
| 対応 OS | macOS 15 以上（BRIEF は macOS 26） | Apple Silicon 主対象 |

外部依存は GRDB 7 のみ。追加する場合は ROADMAP の判断事項として扱う。

---

## 2. 処理パイプライン

### 2.1 現状（v0.10）

```
ScreenCaptureKit (5–30fps, 除外アプリと自分の HUD は画像から除去)
  → FrameBuffer (actor; 前フレームは 320px 輝度画像のみ)
  → ChangeDetector (0.25–1s ごと; セル差分, 連続変化は抑制)
  → AnalysisScheduler (落ち着いたら / 最大 2s; OCR は最大 0.5–2fps)
  → OCRService (変化領域のみ) + ImageClassifier (大きな画像変化のみ, 5–10s 間隔)
  → TextBlockGrouper → AIRouter (ルール, ignore-first, Personalization 補正)
  → CooldownCache (5 分) → TranslationProvider
  → HUD ─┬→ BRIEF (Foundation Models, 非同期, 5s タイムアウト)
         └→ IntelStore (表示した内容を SQLite に記録)
```

この経路に、ポインタ滞在からの優先解析、QR・顔の有無・秘密情報の検出、Coding Mode の説明、画面共有中の警告、必要時の Gemini 識別が加わる。別経路の `ActivityTracker` は前面ページを 2 秒ごとに観測し、閲覧記録・ブックマーク・作業セッションを作る。`ContextIntelCoordinator` はページ変更時に作品・ニュースのカードを判断する。

### 2.2 将来案

字幕・Terminal などの専用領域検出、日付・金額の抽出、汎用 Web 検索 API、大規模な履歴向けの検索索引は未実装。現在の処理は上記の v0.10 経路と §3 の各コンポーネントを参照。

---

## 3. モジュール構成

`Sources/AmbientCore` は画面に依存しない純粋ロジック（Linux でもビルド・テスト可）、`Sources/AmbientApp` は macOS 専用の実装。新しいロジックはまず Core に置き、テストを書く。

| モジュール | 主な実装 | 残る課題・将来案 |
| --- | --- | --- |
| Capture | `ScreenCaptureManager`, `FrameBuffer`, `FrameConverter` | `WindowTracker`（ウィンドウ単位の対象指定） |
| Vision | `ChangeDetector`, `AnalysisScheduler`, `OCRService`, `ImageClassifier`, `TextBlockGrouper`, `FaceDetector`, QR 検出 | 字幕・Terminal などの専用領域検出 |
| Intelligence | `AIRouter`, `InterestScorer`, `AppleIntelligenceReasoner`, `ErrorDetector`, `TermExtractor`, `AnalysisPipeline` | より細かい領域・文脈の判定 |
| AI / Cloud | `AppleIntelligenceBriefingProvider`, `GeminiProvider`, `NetworkGate`。`AIProvider` / `LocalAIProvider` は別の抽象化として存在 | 汎用 Web 検索 API |
| Context | `ActivityTracker`, `ContextIntelCoordinator`, `MediaContext`, `BrowserURLProvider` | スクロール速度などの活用 |
| Memory | `IntelStore` / `IntelDatabase`（GRDB）、`VisualMemoryIndex`, `NLTextEmbedding` | 大規模データ向けの索引 |
| Privacy | `PrivacyPolicy`, `PrivacyManager`, `SensitiveDataDetector`, `ScreenShareMonitor`, `RedactionOverlayController` | 共有中の黒塗りの実機検証 |
| UI | `OverlayWindowController`, `HUDCardView`, `ArchiveView`, `SettingsView`, `OnboardingView` | 実機での操作・アクセシビリティ検証 |

---

## 4. 主要コンポーネント設計

### 4.1 Change Detector

- 現状: 320px 幅の輝度画像を 8px セルに分け、閾値を超えて変化した画素の比率で判定。近い領域は結合、小さすぎる変化は無視。動画など変化し続けるセルは抑制し、止まった時点で一度だけ報告する。
- 改善候補（必要になってから）: 知覚ハッシュでの全体比較による早期打ち切り、SSIM。実機計測で CPU に余裕がなければ採用しない。

### 4.2 AI Router

- 1 段目（常時）: ルールベース。各候補に `InterestScore`（0〜1）を付け、0.7 以上だけ表示。
- 2 段目: 1 段目で「判断が割れる」候補（0.5〜0.7）だけを Foundation Models に渡して判定する。LLM が使えない環境では 1 段目のみ。
- 出力は `RoutedAction`（action / confidence / importance / region / payload）。

#### 4.2.1 LLM ルーターのプロンプト（原文）

```
You are an ambient screen intelligence router.
Analyze the supplied screen region.
Your task is NOT to describe everything visible.
Determine whether anything currently visible would be genuinely useful to explain to the user.
Possible actions: translate, identify_person, identify_animal, identify_plant, identify_landmark,
explain_term, explain_error, identify_product, ignore
Prefer ignore. Only return information if it is likely to provide meaningful value.
Avoid obvious information. Avoid repeatedly explaining common concepts.
Return structured JSON.
```

出力例:

```json
{ "action": "identify_animal", "confidence": 0.88, "importance": 0.76,
  "region": { "x": 0.32, "y": 0.14, "width": 0.28, "height": 0.41 } }
```

Foundation Models では `@Generable` の構造体で受け取り、JSON 文字列の解析は行わない。

### 4.3 HUD と More 操作

- 現状: 画面全体を覆うクリック透過パネルに、レティクル・引き出し線・カードを描画。ホバーはポインタ位置のポーリングで検出。
- カード部分だけを別の小さな `NSPanel` に分け、ポインタがカード上に 0.6 秒以上留まったときだけ `ignoresMouseEvents = false` にして More 操作を出す。離れたら元に戻す。

### 4.4 Translation

- 言語モデルの自動ダウンロードはしない（未インストール時は何も表示しない）。
- macOS 15 のブリッジ方式は実機で要確認（ROADMAP M0）。

### 4.5 プロバイダの抽象化

| プロトコル | 役割 | 実装 |
| --- | --- | --- |
| `TranslationProvider` | 翻訳 | `AppleTranslationProvider` |
| `LanguageIdentifying` | 言語判定 | `NLLanguageIdentifier` |
| `BriefingProvider` | 一行補足 | `AppleIntelligenceBriefingProvider` |
| `TextEmbedding` | 文埋め込み | `NLTextEmbedding` |
| `InterestAdjusting` | 個人化 | `PersonalizationStore` |
| `VisualMemoryStore` | 記憶 | `IntelStore`（SQLite） |
| `AIProvider` | 画像＋文脈の解析 | `LocalAIProvider`（ルールベース） |
| `CloudIdentifying` / `MediaResearching` | 識別・作品・ニュースの情報取得 | `GeminiProvider`（オプトイン） |

---

## 5. データ設計

### 5.1 現状（v0.10）

| データ | 保存先 | 内容 |
| --- | --- | --- |
| 設定 | `UserDefaults` | 翻訳先言語、モード、除外アプリ、表示位置など |
| Personalization | `UserDefaults`（JSON） | `action:…|lang:…|app:…` ごとの重み（−0.3〜+0.3） |
| Visual Memory・閲覧記録・セッション・エンティティ・Knowledge Cache | `Application Support/AmbientScreenIntelligence/intel.sqlite`（GRDB） | HUD に表示した Intel と、設定で有効な場合のページのタイトル・URL・閲覧時間。保持 1/7/30 日（ブックマークを除く）、バックアップ除外。v0.4 の `visual-memory.json` は初回起動時に取り込んで削除 |
| フレーム | メモリのみ | 保存しない |

### 5.2 スキーマの概略（SQLite）

以下はテーブル間の関係を示す概略であり、実際のカラム・索引・FTS5 trigram の定義は `Sources/AmbientStore/IntelDatabase.swift` の v1 / v2-sessions マイグレーションを正とする。

| テーブル | 内容 |
| --- | --- |
| `observation` | HUD の元となった観測、または閲覧したページ。v2 でセッション ID・閲覧時間・ページキーを追加 |
| `intel` | HUD に表示した本文・種別・重要度・フィードバック |
| `entity` / `observation_entity` | 固有名詞・用語と観測の対応 |
| `knowledge` | 用語などの説明と有効期限 |
| `embedding` | 検索用の文埋め込み |
| `intel_fts` | 日本語の部分一致にも使う FTS5 trigram 索引 |
| `work_session` / `bookmark` | v2 で追加した作業セッションと自動ブックマーク |

移行方針: 起動時に `visual-memory.json` があれば `observation` ＋ `intel` に取り込み、成功したら JSON を削除する。

保持: `observation` / `intel` は設定した保持期間（1/7/30 日）で削除。`entity` / `knowledge` は参照がなくなるか期限切れで削除。ブックマークされたものは保持期間の対象外（ユーザーが明示的に消すまで残す）。

---

## 6. プライバシー設計

### 6.1 原則

| ID | 原則 | 実装 |
| --- | --- | --- |
| PD-1 | フレーム画像はディスクに保存しない | メモリのみ。前フレームは 320px 輝度画像 |
| PD-2 | Local First | OCR・翻訳・主要な判定はオンデバイス。Gemini による識別・作品・ニュースの補足はオプトイン |
| PD-3 | 除外アプリはキャプチャ画像から除去し、解析もしない | `SCContentFilter` の除外＋前面アプリの判定 |
| PD-4 | パスワード系ウィンドウでは解析しない | タイトルのキーワード判定 |
| PD-5 | ログに認識テキストを出さない | 件数・文字数・言語コードのみ |
| PD-6 | 記録するのは派生データのみ | Visual Memory はテキストとメタデータのみ。バックアップ除外 |
| PD-7 | クラウド送信はオプトイン。画像は切り抜き領域のみ、作品・ニュース・公人の補足では必要なテキストを送る | `NetworkGate`（オプトイン・キー・Battery・許可ホスト）、`ImageCropper`、秘密情報を含む領域は送らない。送信履歴（目的・ホスト・サイズ）を設定画面に表示 |
| PD-8 | ユーザーがいつでも止められ、消せる | Pause、記録オフ、全削除 |

### 6.2 データの流れと保存先

| データ | 端末外に出るか | 保存 | 保持 |
| --- | --- | --- | --- |
| 画面フレーム | 出ない | しない | — |
| OCR テキスト（解析中） | 公人の判定時には画面上の人名と周辺テキストを送る場合がある | HUD に表示したもの以外は保存しない | — |
| HUD に表示した Intel | 出ない | SQLite | 1/7/30 日 |
| 閲覧したページのタイトル・サニタイズ済み URL・閲覧時間 | ニュース見出しや作品タイトルを Gemini に送る場合がある | SQLite（記録を有効にした場合） | 1/7/30 日。ブックマークは残す |
| Personalization の重み | 出ない | UserDefaults | 無期限（リセット可） |
| クラウドに送る切り抜き（v0.8〜） | **出る**（オプトイン時のみ） | 端末には保存しない | プロバイダの規約に従う |
| 作品タイトル・ニュース見出し・公人名と周辺テキスト | **出る**（Gemini 有効時のみ） | 知識キャッシュなどの派生データ | 用途に応じる |

### 6.3 権限と Entitlement の変遷

| 時期 | 追加するもの | 理由 | ユーザーへの見せ方 |
| --- | --- | --- | --- |
| v0.1〜 | 画面収録（TCC）、App Sandbox、Hardened Runtime | 画面取得 | 初回起動時 |
| v0.7 | なし（ポインタ位置・クリップボードの変化回数は権限不要） | Interest Region、自動ブックマーク | — |
| v0.7 | Apple Events（`com.apple.security.automation.apple-events` と対象ブラウザの temporary exception、`NSAppleEventsUsageDescription`） | ブラウザの URL（D-5 決定） | macOS がブラウザごとに初回だけ確認。設定でオフ可 |
| v0.8 | `com.apple.security.network.client`（D-4 決定） | Gemini による識別（D-2 決定） | 設定でオプトインし API キー（キーチェーン保存）を入れるまで通信しない。通信先は Gemini API のみ |
| v1.0 以降 | マイク、音声認識 | Audio Intelligence | 機能単位でオプトイン |

ネットワーク Entitlement を付けた後も「オプトインするまで一切通信しない」ことを、通信層を 1 か所（`NetworkGate`）に集約して保証する。

### 6.4 秘密情報の扱い（SC-1〜3）

- 検出は正規表現＋検証（クレジットカードは Luhn、AWS キーは接頭辞と長さ等）。検出結果の値そのものは保存・ログしない（種類と位置のみ）。
- 秘密情報を含む領域は、クラウド送信・Visual Memory への記録から自動的に除外する。
- 画面共有中の判定: 共有ツールが前面にあり、かつ共有中インジケータが出ている状態を `ScreenShareMonitor` で推定する（確実な API はないため、誤判定時は警告のみに留める）。

---

## 7. 品質保証

| 対象 | 方法 |
| --- | --- |
| 純粋ロジック（Core） | XCTest。Linux と macOS の CI で実行 |
| アプリのビルド | CI で Xcode 16（macOS 15）と Xcode 26（macOS 26）の両方 |
| 実機の動作 | ROADMAP の「実機検証チェックリスト」を各マイルストーンで実施 |
| 性能 | Instruments（Time Profiler・Allocations・Energy Log）で NF-1〜4 を計測し、結果を `docs/perf/` に残す |
