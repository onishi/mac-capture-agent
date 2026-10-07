# CLAUDE.md — 開発ルール

Ambient Screen Intelligence: macOS の画面を常時観察し、価値があるときだけ HUD で補足する Local Only のメニューバーアプリ。

## 文書

- 利用者向け: `docs/MANUAL.md`（使い方・設定・困ったとき）
- 要件: `docs/SPEC.md`（要件 ID と実装状態の正本）
- 設計: `docs/ARCHITECTURE.md`（構成・ローカル AI の方針と推定の表示・データ・プライバシー）
- 計画: `docs/ROADMAP.md`（現在地・次にやること・アイデアのバックログ・判断事項・リスク）
- 実機検証: `docs/CHECKLIST.md`（結果は `docs/perf/`）
- 配布: `docs/RELEASE.md`

文書を増やさない。新しい内容は上のどれかに入れる（重複させない）。

## 構成

- `Sources/AmbientCore` — 画面に依存しない純粋ロジック。Foundation のみ（CGRect を使うファイルは `#if canImport(CoreGraphics) import CoreGraphics #endif`）。Linux でもビルド可。
- `Sources/AmbientStore` — SQLite（GRDB）の保存層。macOS 専用。Core を使うファイルは `#if canImport(AmbientCore) import AmbientCore #endif`（Xcode では同じモジュールになるため）。テストは `Tests/AmbientStoreTests`（macOS の `swift test` で実行、Linux ではスキップ）。
- `Sources/AmbientApp` — macOS 専用（ScreenCaptureKit / Vision / AppKit / SwiftUI / Translation / Foundation Models）。
- `Tests/AmbientCoreTests` — Core の XCTest。
- `AmbientScreenIntelligence.xcodeproj` — Xcode 16 の同期フォルダ。上の 3 フォルダ（Core / Store / App）にファイルを置けば自動でアプリに含まれる。アプリ側のファイルは Core を `import` しない（同じモジュールにコンパイルされる）。

## コマンド

- テスト: `swift test`
- アプリのビルド: `xcodebuild -project AmbientScreenIntelligence.xcodeproj -scheme AmbientScreenIntelligence -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- CI: `.github/workflows/ci.yml`（Linux のコアテスト、macOS 15 / 26 でのビルドとテスト）

## ルール

- 表示しないことを優先する。Router の既定は ignore、失敗時は何も表示しない。
- 画面画像はディスクに保存しない。ログに認識テキストを出さない（件数・文字数・言語コードのみ）。
- 新しいロジックはまず Core に値型・純粋関数として書き、テストを付ける。
- Swift 5 言語モード。Swift Concurrency を使い、メインスレッドで解析しない。`@MainActor` は UI だけ。
- 強制アンラップと `fatalError` を使わない。
- クラウド LLM・外部 API は使わない。アプリは通信しない（ROADMAP D-7）。精度が低くてもローカル（ルール → Apple のオンデバイス ML → Foundation Models）で実装し、推定は推定と表示する。
- LLM の自己申告の確度は信用しない。画面上の文字で裏付けがあるときだけ断定し、Apple Intelligence が無い環境でも動くルールの経路を残す。
- 新しい権限・Entitlement・外部依存（ローカルモデルを含む）は、`docs/ROADMAP.md` の判断事項を確認してから追加する。
- 機能を追加・変更したら、SPEC の状態列、MANUAL（利用者に見えるもの）、CHECKLIST（実機で確認すべき点）を更新し、ROADMAP のバックログから消す。README は概要と案内だけにする。
- 実機での動作は未検証の部分が多い。実機で確認すべき点は報告に必ず書く。

## 作業の進め方

1. ROADMAP §2 の上から 1 つ選び、1 タスク＝1 コミット程度に分ける。
2. 判定・抽出・整形は Core に純粋関数で書き、テストを付ける（Apple Intelligence が無くても動く部分を必ず作る）。LLM を使う部分は `AppleIntelligenceReasoner` の拡張に書き、指示文は Core に置いてテストで確認する。
3. 表示条件は厳しくする（ユーザー操作起点、ポインタ滞在、画面上の文字での裏付け）。推定には出典と「かもしれません」を付ける。
4. 作業ブランチに push し、CI（Linux のコアテスト＋macOS 15 / 26 のビルドとテスト）が通ってから main にマージする。
5. 完了時の報告: 実装した要件 ID、主な変更、技術的判断、実機で確認すべき点、既知の制限。
