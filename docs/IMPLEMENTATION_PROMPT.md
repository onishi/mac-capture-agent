# 開発プロンプト（Claude Code / Codex 用）

このリポジトリで次のマイルストーンを実装させるときに、そのまま渡せるプロンプト。
「共通プロンプト」の後ろに、着手するマイルストーンの「個別プロンプト」を 1 つ続けて渡す。

---

## 共通プロンプト

```
あなたは熟練した macOS アプリケーションエンジニアです。
このリポジトリ（Ambient Screen Intelligence）の開発を続けてください。

まず次を読んでから作業を始めてください。
- CLAUDE.md（開発ルール）
- docs/SPEC.md（要件。要件 ID と状態列）
- docs/ARCHITECTURE.md（構成・データ設計・プライバシー設計）
- docs/ROADMAP.md（今回のマイルストーンの範囲と完了条件、判断事項）

最重要方針:
- 何を表示するかより、何を表示しないか。Router の既定は ignore。
- Local First。画面画像はディスクに保存しない。ログに認識テキストを出さない。
- 失敗時は何も表示しない（ログのみ）。

作業の進め方:
1. 今回のマイルストーンのタスクを、1 タスク＝1 コミット程度に分けて計画する。
2. 新しいロジックは Sources/AmbientCore に純粋な値型・関数として書き、Tests/AmbientCoreTests にテストを書く。
3. macOS 固有の処理（ScreenCaptureKit / Vision / AppKit / SwiftUI / Translation / Foundation Models）は Sources/AmbientApp に置く。
4. `swift test` が通ることを確認してからコミットする。Xcode でのビルドは CI（.github/workflows/ci.yml）で確認する。
5. ROADMAP の「判断が必要な事項」に関わる変更（新しい権限・Entitlement・外部依存・ネットワーク通信）は、勝手に決めずに確認を求める。
6. 完了したら、SPEC.md の状態列、README の機能一覧と既知の制限を更新する。

完了時の報告: 実装した要件 ID、主な変更、新規ファイル、技術的判断、実機で確認すべき点、既知の制限。
```

---

## 個別プロンプト

### M0 — 実機検証と安定化（v0.4.1）

```
今回は ROADMAP の M0 を行います。機能追加はしません。

1. 設定に隠しオプション「Debug overlay」を追加し、オンのとき次を HUD レイヤーに重ねて表示する。
   - ChangeDetector が出した変化領域（細い枠）
   - OCR を実行した領域と、認識した行数
   - Router の候補ごとのアクション・スコア・採否（採用は色を変える）
   - パイプラインの処理時間（差分・OCR・翻訳）
   表示内容はログと同様に認識テキストを含めない（スコアと件数のみ）。
2. 計測用に、パイプラインの各段の所要時間を OSSignposter で記録する。
3. docs/ROADMAP.md §5 のチェックリストを、私（ユーザー）が実機で確認しやすいよう
   docs/perf/CHECKLIST-v0.4.1.md として「手順・期待結果・結果記入欄」の表にする。
4. 私が実機で見つけた不具合を報告したら、再現手順を Core のテストに落とせるものは落としてから修正する。
```

### M1 — 土台の強化（v0.5）

```
今回は ROADMAP の M1 を行います。判断事項 D-1（SQLite）は GRDB を推奨としていますが、
導入前に確認を求めてください。

順序:
1. SQLite 層（ARCHITECTURE §5.2 のスキーマ、マイグレーション v1）。
   起動時に visual-memory.json を取り込み、成功したら削除。VisualMemoryStore の SQLite 実装、FTS5 検索。
   既存の VisualMemoryIndex のテストと同等の検索結果になることをテストで示す。
2. Pause Until Tomorrow（PV-4）。
3. HUD の DetailPanel（HD-4）: ARCHITECTURE §4.3 の方針どおり、カードだけを別パネルにし、
   ホバー 0.6 秒でクリック可能にする。操作: コピー / 覚える / 今後表示しない / 詳しく見る（Archive で開く）。
   操作しないときは下のアプリのクリックを妨げないこと。
4. Personalization の重みを仕様（閉じる −1 / More +2 / 検索 +3）に合わせて換算。
5. 固有名詞抽出（NLTagger）→ entity / observation_entity への記録（EX-1）。
6. 専門用語の解説（EX-2）: 候補抽出のルールを Core に書き（英字略語・カタカナ語など、一般語は除外）、
   Foundation Models で 2 行の説明を生成し knowledge に 30 日キャッシュ。HUD は kind = explanation。
   Apple Intelligence が使えない環境では何もしない。
7. 既知用語（EX-3）と再登場通知（VM-3）。
8. LLM ルーター（RT-5）: スコア 0.5〜0.7 の候補だけを Foundation Models の @Generable 出力で判定。
```

### M2 — Coding Mode と秘密情報（v0.6）

```
今回は ROADMAP の M2 を行います。

1. Coding Mode の切替（CD-1）。AppContextClassifier を拡張し、ブラウザの GitHub もタイトルで判定。
2. エラー検出ルール（CD-3, CD-4）を Core に実装。言語・ツール別の代表的なエラー 10 種以上と、
   正常ログ（ビルド成功・テスト成功・警告のみ）をテストコーパスにして、誤検出しないことを示す。
3. エラー説明（explain_error）を Foundation Models で 1〜2 行。
4. SensitiveDataDetector（SC-1）を Core に実装。値は返さず、種類と位置だけを返す。
   カード番号は Luhn、各種 API キーは接頭辞と長さで検証。誤検出率をテストで計測。
5. ScreenShareMonitor と、共有中の警告 HUD（SC-2）。
6. 秘密情報を含む領域を Visual Memory から除外。
7. 実験機能（設定で既定オフ）: 共有中の秘密情報を不透明な矩形で覆う（SC-3）。
```

### M3 — 注目と作業コンテキスト（v0.7）

```
今回は ROADMAP の M3 を行います。D-5（ブラウザ URL の取得）は確認を求めてから実装してください。

1. Interest Region（CX-1）: AnalysisScheduler に優先度を追加し、ポインタが 2 秒以上留まった領域を先に解析。
2. 自動ブックマーク（VM-5）: スコアの計算は Core の純粋関数にし、要素（滞在・再訪・コピー・ポインタ滞在・スクロールの遅さ）ごとにテスト。
   入力監視の権限は使わない（スクロールはフレーム差分から推定）。
3. 作業セッション（CX-2）: 観測のクラスタリングを Core に実装しテスト。名前付けは Foundation Models（無ければアプリ名とタイトルから生成）。
4. 作業復元（CX-3）とデイリーサマリー（CX-4）を Archive に追加。
5. URL / QR / 日付 / 金額の検出（SI-9）。
```

### M4 — クラウドと Web（v0.8）

```
今回は ROADMAP の M4 を行います。D-2・D-3・D-4 は着手前に必ず確認を求めてください。
ネットワーク Entitlement の追加は確認が取れてから行います。

1. NetworkGate: すべての通信をここに集約。オプトイン前は通信しない。送信前に SensitiveDataDetector を通す。
   送信内容のプレビューを設定画面に出す。
2. SearchProvider（Wikipedia REST から）と Knowledge Cache（30 日）。
3. CloudAIProvider（切り抜きのみ送信、API キーは Keychain）。
4. 動植物・ランドマークの識別（ID-1〜3）。確信度が低い場合は「〜の可能性があります」。
5. Battery モードではクラウドを使わない。
完了条件として、オプトイン前に通信が発生しないことを確認した手順と結果を docs/ に残す。
```
