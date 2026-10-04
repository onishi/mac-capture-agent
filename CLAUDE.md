# CLAUDE.md — 開発ルール

Ambient Screen Intelligence: macOS の画面を常時観察し、価値があるときだけ HUD で補足する Local First のメニューバーアプリ。

## 文書

- 要件: `docs/SPEC.md`（要件 ID と実装状態）
- 設計: `docs/ARCHITECTURE.md`（構成・データ・プライバシー）
- 計画: `docs/ROADMAP.md`（マイルストーン・完了条件・判断事項・実機チェックリスト）
- 着手用プロンプト: `docs/IMPLEMENTATION_PROMPT.md`

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
- 新しい権限・Entitlement・外部依存・ネットワーク通信は、`docs/ROADMAP.md` の判断事項を確認してから追加する。
- 機能を追加・変更したら `docs/SPEC.md` の状態列と `README.md` を更新する。
- 実機での動作は未検証の部分が多い。実機で確認すべき点は報告に必ず書く。
