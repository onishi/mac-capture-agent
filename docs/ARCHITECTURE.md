# 技術構成・データ設計・プライバシー設計

要件は [SPEC.md](SPEC.md)、実装順は [ROADMAP.md](ROADMAP.md)。本書は「現状（As-Is, v0.4）」と「目標（To-Be, v1.0）」を並べて記述する。

---

## 1. 技術スタック

| 層 | 採用 | 備考 |
| --- | --- | --- |
| 言語 / UI | Swift 5 モード、SwiftUI ＋ AppKit | Swift Concurrency（actor / async） |
| 画面取得 | ScreenCaptureKit (`SCStream`) | BGRA、IOSurface のままメモリで処理 |
| 画像解析 | Vision（OCR・画像分類）、Core ML（将来） | |
| 言語 | NaturalLanguage（言語判定・文埋め込み・固有名詞抽出） | |
| 翻訳 | Translation framework | macOS 26 は `TranslationSession` 直接、15 は SwiftUI ブリッジ |
| ローカル LLM | Foundation Models（macOS 26 + Apple Intelligence） | 現在は BRIEF のみ |
| 永続化 | 現状: JSON ファイル → 目標: SQLite（GRDB、ROADMAP D-1） | |
| ベクトル検索 | 現状: 全件コサイン類似度 → 目標: 1 万件規模まで同方式、それ以上は sqlite-vec / USearch | |
| クラウド AI | `AIProvider` プロトコルで抽象化（未実装） | オプトイン |
| CI | GitHub Actions: Linux でコアのテスト、macOS 15 / 26 でアプリのビルドとテスト | |
| 対応 OS | macOS 15 以上（BRIEF は macOS 26） | Apple Silicon 主対象 |

外部依存は現在ゼロ。追加する場合は ROADMAP の判断事項として扱う。

---

## 2. 処理パイプライン

### 2.1 現状（v0.4）

```
ScreenCaptureKit (5–30fps, 除外アプリと自分の HUD は画像から除去)
  → FrameBuffer (actor; 前フレームは 320px 輝度画像のみ)
  → ChangeDetector (0.25–1s ごと; セル差分, 連続変化は抑制)
  → AnalysisScheduler (落ち着いたら / 最大 2s; OCR は最大 0.5–2fps)
  → OCRService (変化領域のみ) + ImageClassifier (大きな画像変化のみ, 5–10s 間隔)
  → TextBlockGrouper → AIRouter (ルール, ignore-first, Personalization 補正)
  → CooldownCache (5 分) → TranslationProvider
  → HUD (SpyHUDView) ─┬→ BRIEF (Foundation Models, 非同期, 5s タイムアウト)
                      └→ VisualMemory (表示したものだけ記録)
```

### 2.2 目標（v1.0）

```
Capture → FrameBuffer → ChangeDetector → RegionDetector（字幕/画像/人物/Terminal/コード）
  → Local Vision（OCR, 分類, バーコード, 顔の有無, NSDataDetector）
  → EntityResolver（NLTagger + Knowledge Cache 照合）
  → AI Router（ルール → 必要時のみ Foundation Models ルーター）
  → Local Processing（翻訳, 解説, エラー説明, 秘密情報検出）
  → 必要時のみ・オプトイン: Cloud AI（切り抜きのみ）→ Web Search → Knowledge Cache
  → HUD / DetailPanel / 警告
  → ObservationStore（SQLite）→ Session/Context 推定, 自動ブックマーク, サマリー
```

追加の入力源: Interest Region（ポインタ滞在）、クリップボード変化（`changeCount`）、画面共有の検出。

---

## 3. モジュール構成

`Sources/AmbientCore` は画面に依存しない純粋ロジック（Linux でもビルド・テスト可）、`Sources/AmbientApp` は macOS 専用の実装。新しいロジックはまず Core に置き、テストを書く。

| 仕様上のモジュール | 現状のファイル | 目標で追加するもの |
| --- | --- | --- |
| Capture | `ScreenCaptureManager`, `FrameBuffer`, `FrameConverter` | `WindowTracker`（ウィンドウ単位の対象指定） |
| Vision | `ChangeDetector`, `AnalysisScheduler`, `OCRService`, `ImageClassifier`, `TextBlockGrouper`, `NLLanguageIdentifier` | `RegionDetector`, `BarcodeDetector`, `DataDetector`, `FaceDetector`（有無のみ） |
| Intelligence | `AIRouter`, `InterestScorer`, `Personalization`, `CooldownCache`, `AppContextClassifier`, `AnalysisPipeline`, `Briefing` | `ContextAnalyzer`, `EntityResolver`, `ErrorAnalyzer`, `TermExplainer`, `LLMRouter` |
| AI | `AIProvider`（プロトコル）, `AppleIntelligenceBriefingProvider` | `LocalAIProvider`, `CloudAIProvider` |
| Search | — | `SearchProvider`, `KnowledgeResolver`, `KnowledgeCache` |
| Memory | `VisualMemoryEntry`, `VisualMemoryIndex`, `MemoryQueryParser`, `FileVisualMemoryStore`, `NLTextEmbedding` | `ObservationStore`, `EntityStore`, `EmbeddingStore`, `SearchIndex`（SQLite） |
| Privacy | `PrivacyPolicy`, `PrivacyManager`, `ForegroundContextProvider` | `SensitiveDataDetector`, `ScreenShareMonitor`, `RedactionOverlay` |
| UI | `OverlayWindowController`, `SpyHUDView`, `HUDCardView`, `MenuBarController`, `SettingsView`, `ArchiveView` | `DetailPanel`（More 操作）, `SessionView`, `DailySummaryView`, オンボーディング |

---

## 4. 主要コンポーネント設計

### 4.1 Change Detector

- 現状: 320px 幅の輝度画像を 8px セルに分け、閾値を超えて変化した画素の比率で判定。近い領域は結合、小さすぎる変化は無視。動画など変化し続けるセルは抑制し、止まった時点で一度だけ報告する。
- 改善候補（必要になってから）: 知覚ハッシュでの全体比較による早期打ち切り、SSIM。実機計測で CPU に余裕がなければ採用しない。

### 4.2 AI Router

- 1 段目（常時）: ルールベース。各候補に `InterestScore`（0〜1）を付け、0.7 以上だけ表示。
- 2 段目（v0.5〜）: 1 段目で「判断が割れる」候補（0.5〜0.7）だけを Foundation Models に渡し、§4.2.1 のプロンプトで判定する。LLM が使えない環境では 1 段目のみ。
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

### 4.3 HUD と DetailPanel

- 現状: 画面全体を覆うクリック透過パネルに、レティクル・引き出し線・カードを描画。ホバーはポインタ位置のポーリングで検出。
- 課題: More 操作（HD-4）にはクリックが必要だが、全画面パネルをクリック可能にすると下のアプリを塞ぐ。
- 方針: カード部分だけを別の小さな `NSPanel` に分け、ポインタがカード上に 0.6 秒以上留まったときだけ `ignoresMouseEvents = false` にして More 操作を出す。離れたら元に戻す。

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
| `VisualMemoryStore` | 記憶 | `FileVisualMemoryStore` → SQLite 実装 |
| `AIProvider` | 画像＋文脈の解析 | `LocalAIProvider` → `CloudAIProvider`（オプトイン） |
| `SearchProvider`（予定） | Web 検索 | Wikipedia REST → 汎用検索 API |

---

## 5. データ設計

### 5.1 現状（v0.4）

| データ | 保存先 | 内容 |
| --- | --- | --- |
| 設定 | `UserDefaults` | 翻訳先言語、モード、除外アプリ、表示位置など |
| Personalization | `UserDefaults`（JSON） | `action:…|lang:…|app:…` ごとの重み（−0.3〜+0.3） |
| Visual Memory | `Application Support/AmbientScreenIntelligence/visual-memory.json` | `VisualMemoryIndex`（HUD に表示した Intel、最大 1,000 件、保持 1/7/30 日、バックアップ除外） |
| フレーム | メモリのみ | 保存しない |

### 5.2 目標スキーマ（SQLite, v0.5 で移行）

仕様の Observation / Entity / ObservationEntity / Knowledge に、現状の Intel を加える。

```sql
-- 画面上で何かを観測した事実（画像は持たない）
CREATE TABLE observation (
  id            TEXT PRIMARY KEY,          -- UUID
  timestamp     REAL NOT NULL,             -- Unix 時刻
  application   TEXT,                      -- 表示名
  bundle_id     TEXT,
  window_title  TEXT,
  url           TEXT,                      -- 取得できた場合のみ（D-5）
  screen_id     INTEGER,                   -- CGDirectDisplayID
  region_x REAL, region_y REAL, region_w REAL, region_h REAL,  -- 正規化座標
  category      TEXT NOT NULL,             -- foreign_text / term / animal / error ...
  confidence    REAL NOT NULL,
  text          TEXT,                      -- 認識テキスト（上限 1,000 文字）
  session_id    TEXT REFERENCES work_session(id)
);
CREATE INDEX observation_time ON observation(timestamp);

-- HUD に表示した内容（現在の VisualMemoryEntry に相当）
CREATE TABLE intel (
  id             TEXT PRIMARY KEY,
  observation_id TEXT NOT NULL REFERENCES observation(id) ON DELETE CASCADE,
  kind           TEXT NOT NULL,            -- translation / explanation / identification / warning
  title          TEXT, body TEXT NOT NULL, briefing TEXT,
  source_lang    TEXT, target_lang TEXT,
  importance     REAL NOT NULL,
  feedback       TEXT                      -- hovered / dismissed / opened / searched
);

-- 固有名詞・用語・種などの実体
CREATE TABLE entity (
  id             TEXT PRIMARY KEY,
  type           TEXT NOT NULL,            -- person / org / place / product / term / species / landmark / work
  name           TEXT NOT NULL,
  canonical_name TEXT NOT NULL,
  metadata       TEXT,                     -- JSON
  known          INTEGER NOT NULL DEFAULT 0, -- ユーザーが「今後表示しない」にした
  UNIQUE(type, canonical_name)
);

CREATE TABLE observation_entity (
  observation_id TEXT NOT NULL REFERENCES observation(id) ON DELETE CASCADE,
  entity_id      TEXT NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
  confidence     REAL NOT NULL,
  PRIMARY KEY (observation_id, entity_id)
);

-- エンティティの解説（Knowledge Cache）
CREATE TABLE knowledge (
  entity_id  TEXT PRIMARY KEY REFERENCES entity(id) ON DELETE CASCADE,
  summary    TEXT NOT NULL,
  source     TEXT NOT NULL,                -- foundation-models / wikipedia / cloud:<provider>
  updated_at REAL NOT NULL,
  expires_at REAL NOT NULL                 -- 既定 30 日
);

-- 埋め込み（Float32 の BLOB）
CREATE TABLE embedding (
  owner_type TEXT NOT NULL,                -- intel / observation / entity
  owner_id   TEXT NOT NULL,
  model      TEXT NOT NULL,                -- nl-sentence-ja など
  vector     BLOB NOT NULL,
  PRIMARY KEY (owner_type, owner_id, model)
);

-- 作業セッション（CX-2）
CREATE TABLE work_session (
  id TEXT PRIMARY KEY, title TEXT, started_at REAL NOT NULL, ended_at REAL,
  apps TEXT, summary TEXT
);

-- 自動ブックマーク（VM-5）
CREATE TABLE bookmark (
  observation_id TEXT PRIMARY KEY REFERENCES observation(id) ON DELETE CASCADE,
  score REAL NOT NULL, reasons TEXT NOT NULL   -- JSON: dwell / revisit / copy ...
);

-- 全文検索
CREATE VIRTUAL TABLE intel_fts USING fts5(title, body, briefing, content='intel', content_rowid='rowid');
```

移行方針: 起動時に `visual-memory.json` があれば `observation` ＋ `intel` に取り込み、成功したら JSON を削除する。

保持: `observation` / `intel` は設定した保持期間（1/7/30 日）で削除。`entity` / `knowledge` は参照がなくなるか期限切れで削除。ブックマークされたものは保持期間の対象外（ユーザーが明示的に消すまで残す）。

### 5.3 Codable なイベント表現

外部連携・エクスポート用の形式（仕様 §16 準拠）:

```json
{ "timestamp": "2026-10-04T21:34:00+09:00", "application": "Safari", "windowTitle": "…",
  "url": "…", "entities": ["BMW M2"], "summary": "…", "embedding": [0.01, …] }
```

---

## 6. プライバシー設計

### 6.1 原則

| ID | 原則 | 実装 |
| --- | --- | --- |
| PD-1 | フレーム画像はディスクに保存しない | メモリのみ。前フレームは 320px 輝度画像 |
| PD-2 | Local First | 現在の機能はすべてオンデバイス |
| PD-3 | 除外アプリはキャプチャ画像から除去し、解析もしない | `SCContentFilter` の除外＋前面アプリの判定 |
| PD-4 | パスワード系ウィンドウでは解析しない | タイトルのキーワード判定 |
| PD-5 | ログに認識テキストを出さない | 件数・文字数・言語コードのみ |
| PD-6 | 記録するのは派生データのみ | Visual Memory はテキストとメタデータのみ。バックアップ除外 |
| PD-7 | クラウド送信は切り抜き領域のみ・オプトイン・送信前に秘密情報検出を通す | v0.8 で実装 |
| PD-8 | ユーザーがいつでも止められ、消せる | Pause、記録オフ、全削除 |

### 6.2 データの流れと保存先

| データ | 端末外に出るか | 保存 | 保持 |
| --- | --- | --- | --- |
| 画面フレーム | 出ない | しない | — |
| OCR テキスト（解析中） | 出ない | しない | — |
| HUD に表示した Intel | 出ない | SQLite（現状 JSON） | 1/7/30 日 |
| Personalization の重み | 出ない | UserDefaults | 無期限（リセット可） |
| クラウドに送る切り抜き（v0.8〜） | **出る**（オプトイン時のみ） | 端末には保存しない | プロバイダの規約に従う |
| Web 検索のクエリ（v0.8〜） | **出る**（エンティティ名のみ） | Knowledge Cache | 30 日 |

### 6.3 権限と Entitlement の変遷

| 時期 | 追加するもの | 理由 | ユーザーへの見せ方 |
| --- | --- | --- | --- |
| 現在 | 画面収録（TCC）、App Sandbox、Hardened Runtime | 画面取得 | 初回起動時 |
| v0.7 | なし（ポインタ位置・クリップボードの変化回数は権限不要） | Interest Region、自動ブックマーク | — |
| v0.7（任意） | Apple Events（ブラウザの URL 取得） | VM-1 の URL | 機能を有効にしたときだけ |
| v0.8 | `com.apple.security.network.client` | クラウド AI・Web 検索 | 設定でオプトインするまで通信しない。README のプライバシー表記を更新 |
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
