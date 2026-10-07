# Ambient Screen Intelligence (v0.11)

ユーザーが見ている画面を AI も一緒に見て、**本当に価値があるときだけ**静かに補足情報を出す macOS メニューバーアプリです。

> 何を表示するかより、何を表示しないかを重視する。

現在は v0.11 です。画面の変化した部分だけを解析し、外国語の翻訳・専門用語やエラーの解説・秘密情報の警告・作業の記憶と復元を行います。**v0.11 からクラウド LLM を使わず、すべて Mac の中で動きます**（アプリは通信しません）。動植物・公人・作品・ニュースの補足は端末内の LLM による「推定」で、精度は高くありません。Apple Intelligence がない Mac でも、略語の展開・単位換算・エラーのヒントはルールだけで動きます。実機での検証が終わったものを v1.0 とします。

## ドキュメント

| 文書 | 内容 |
| --- | --- |
| [docs/SPEC.md](docs/SPEC.md) | 製品仕様（要件 ID と実装状況） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 技術構成・データ設計・プライバシー設計 |
| [docs/CAPABILITIES.md](docs/CAPABILITIES.md) | 今できること・これからのアイデア（利用者向けのまとめ） |
| [docs/LOCAL_AI.md](docs/LOCAL_AI.md) | ローカル AI の方針とアイデア一覧（LA-*） |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 開発計画（マイルストーン・完了条件・判断事項・実機チェックリスト） |
| [docs/RELEASE.md](docs/RELEASE.md) | 署名・公証・DMG の作り方 |
| [docs/IMPLEMENTATION_PROMPT.md](docs/IMPLEMENTATION_PROMPT.md) | Claude Code / Codex にそのまま渡せる開発プロンプト |
| [CLAUDE.md](CLAUDE.md) | 開発ルール |

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
| 外部依存 | GRDB 7（SQLite）のみ。ほかは Apple 純正 Framework |

使用 Framework: ScreenCaptureKit / Vision / NaturalLanguage / Translation / Foundation Models / SwiftUI / AppKit / OSLog

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
2. 初回はガイド（FIELD MANUAL）が開き、機能・必要な権限・任意機能・プライバシーを順に説明します。画面収録を許可すると **Start** が押せるようになります（下記参照）
3. 権限付与後にアプリを再起動し、ガイドの **Start** を押すと `Running` になり、解析が始まります（2 回目以降の起動ではガイドは出ません）
4. ブラウザで外国語（例: フランス語のニュース記事）を開くと、画面右上に翻訳 HUD が数秒表示されます

メニュー:

| 項目 | 動作 |
| --- | --- |
| Running / Paused until … | 現在の状態 |
| Pause 5 Minutes / Pause 30 Minutes | 一定時間キャプチャと解析を完全停止し、自動で再開 |
| Pause Until Tomorrow | 翌朝 6:00 まで停止 |
| Pause | 手動で再開するまで停止 |
| Resume | 再開 |
| Last: … / Not Useful | 直前の HUD を「役に立たない」と学習させ、似た表示を減らす |
| Stop Translating <言語> | 直前の HUD の言語を今後翻訳しない |
| Archive… (⌥⌘K) | Visual Memory の検索ウィンドウを開く（⌥⌘K はどこからでも有効） |
| Summarize Screen (⌥⌘S) | 今の画面を 3 行に要約して HUD に出し、Archive に残す（⌥⌘S はどこからでも有効、Apple Intelligence が必要） |
| Preview HUD | マウスポインタ付近にデモの HUD を表示（見た目の確認用） |
| Translation Languages… | 翻訳言語モデルの設定画面を開く |
| Settings… | 翻訳先言語、モード、除外アプリなど |
| Welcome Guide… | 初回起動ガイドをもう一度開く |
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
| `com.apple.security.app-sandbox` | サンドボックス化。ファイルアクセス・**ネットワーク**の Entitlement は付与していません（v0.11 で `network.client` を削除） |
| `com.apple.security.automation.apple-events`（＋対象ブラウザの temporary exception） | 前面タブの URL を読むため（v0.7）。macOS がブラウザごとに初回だけ許可を求め、設定でオフにできる |
| Hardened Runtime | 有効 |

画面収録は TCC（ユーザー許可）で管理されるため、追加の Entitlement は不要です。

## 実装済みの機能（v0.1〜v0.11）

- **ローカル専用化（v0.11）**: クラウド LLM（Gemini）・通信層・API キー設定・ネットワーク Entitlement を削除。旧版で保存した API キーは起動時にキーチェーンから削除。設計とアイデアは [docs/LOCAL_AI.md](docs/LOCAL_AI.md)
  - **端末内の識別（推定）**: 大きな画像の変化を Vision で分類し、具体的なラベル（例: kingfisher）と周辺の文字を Foundation Models に渡して名前と補足 3 つを推定。LLM は画像を見られないため、画面上の文字に名前が出ているときだけ断定し、それ以外は「〜かもしれません」。20 秒に 1 回まで
  - **公人・作品・ニュース**: 画面に書かれた人名、動画のタイトル、ニュースの見出しから、端末内の LLM の知識で推定（有名な人・作品のみ）。ニュースは最近の出来事を語らせず、一般的な背景と、自分が過去 30 日に読んだ関連記事を表示
  - **略語の展開（AI 不要）**: 画面に「Retrieval-Augmented Generation (RAG)」のような定義が出たら覚えておき、別の場所で RAG を見たときに展開を表示（メモリ上のみ、最大 300 件）
  - **単位換算（AI 不要）**: マイル・°F・フィート・インチ・ポンド・オンス・ガロンなどにポインタを 2 秒置くと `INTEL // CONVERSION` でメートル法に換算（翻訳先が英語のときは出さない）
  - **丸で囲んで調べる**: ⌥（Option）を押しながらポインタで丸を描くと、その範囲を必ず調べる。中身に応じて QR → エラー → 翻訳 → 単位 → 用語 → コード → 写真 → 要点（AI）の順で一番合うものを出し、何も無ければ `NO INTEL`。ポインタと修飾キーは CoreGraphics で読み、追加の権限は不要の見込み（実機未確認）。設定でオフにできる
  - **機能ごとのオン・オフと優先順位**: 設定の「機能と優先順位」で 21 の機能を個別に切り替え、HUD を取り合う 10 の機能は ▲▼ で並べ替えられる（同時に出せるときは上のものが勝つ。丸で囲んだときも同じ）
  - **AI の回答の記録（AI LOG）**: 端末内の LLM の回答を、表示しなかったもの（見送り・フィルタ・失敗）も含めて記録し、Archive の AI LOG タブで検索・コピーできる。保持期間は Archive と同じで、設定でオフにできる
  - **時差・日付の換算（AI 不要）**: 「3pm PST」「15:00 UTC」→ 手元の時刻、`1700000000` や ISO 8601 → 日時、「2026-10-20」「10月20日」「Oct 20」→「13日後（火）」。単位換算と同じく、ポインタを置いたときと丸で囲んだときだけ
  - **アーカイブに質問**: Archive の検索欄で末尾を `?` にして Return を押すと、検索上位の記録だけを根拠に端末内の AI が答え、使った記録を示す（Apple Intelligence が必要）
  - **画面の要約（⌥⌘S）**: 今の画面の文章を端末内の AI が 3 行に要約し、Archive に SUMMARY として残す（メニューの「画面を要約」からも。Apple Intelligence が必要）
  - **辞書（AI 不要）**: Apple Intelligence が無いとき、専門用語を macOS の辞書で引いて意味を出す（丸で囲んだときか、価値が高い候補だけ）
  - **開発向けのルール（AI 不要）**: エラーのカードにスタックトレースの「自分のコード」の行（ライブラリやランタイムを除く）を添える。cron 式にポインタを置くと「5分ごと」「毎週 月〜金 9:00」と説明
  - **マイナンバーの検出**: 秘密情報の検出にマイナンバー（チェックデジット検証）を追加。画面共有中は警告の対象
  - **出典の表示**: カードの下に `SRC ▸ RULE / ON-DEVICE ML / ON-DEVICE AI · ESTIMATE / YOUR HISTORY` を表示し、AI の推定と事実を区別する
  - **エラーのヒント（AI 不要）**: Apple Intelligence が無い・失敗したときも、ModuleNotFoundError・EADDRINUSE・command not found・merge conflict など 25 種類に定型の原因と次の一手

- **メニューバー常駐アプリ**（`LSUIElement`、SwiftUI App + AppKit `NSStatusItem`）
- **Screen Capture**: `SCStream` でメインディスプレイを取得。自分自身の HUD と除外アプリのウィンドウはキャプチャ画像から除去
- **Frame Buffer**: `actor` で previous / current フレームを保持（previous は 320px のグレースケール縮小版のみ）
- **Change Detector**: 縮小グレースケール画像のセル単位差分。ノイズ・カーソル点滅・時計などの小さな変化は無視、近接領域は結合。動画やスクロールのように**変化し続ける領域は抑制**し、止まった瞬間に一度だけ解析
- **Analysis Scheduler**: 変化が落ち着いたら解析（最大 2 秒待ち）。OCR は最大 1fps（Balanced）。大きな変化がなければ OCR しない
- **OCR**: Vision `VNRecognizeTextRequest`（accurate、言語自動判定）を**変化領域だけ**に実行。折り返された行は段落にまとめる
- **言語判定**: NaturalLanguage `NLLanguageRecognizer`。短い文字列（`OK`, `Go`, `AI`, `Mac` など）、UI 定型句、URL・コード、ユーザーが読める言語は無視
- **翻訳**: `TranslationProvider` プロトコルで抽象化。実装は Apple Translation framework（macOS 26 は `TranslationSession` を直接生成、macOS 15 は `.translationTask` ブリッジ経由）
- **画像分類**: Vision `VNClassifyImageRequest` を大きな画像変化に低頻度で実行し、`person / animal / plant / food / landmark / text / unknown` にマッピング。具体的なラベルは端末内の識別（v0.11）の手がかりに使う
- **AI Router（ignore-first）**: ルールベースの `InterestScorer` で 0.0〜1.0 のスコアを付け、0.7 以上のものだけ表示。メニューバー領域の文字やコーディングアプリでは減点
- **Cooldown**: 同じ内容は 5 分間再表示しない（OCR の揺れを吸収する正規化キー）
- **HUD**: 透明・最前面・クリック透過の `NSPanel` + SwiftUI。fade in 300ms → 3〜6 秒表示 → fade out 400ms。画面右上に表示
- **製品化（v0.10）**
  - 初回起動ガイド（6 ステップ。画面収録が許可されるまで開始しない。メニューから再表示可能）
  - 日本語ローカライズ（メニュー・設定・ガイド。HUD のコードネームなどの演出文字は英語）
  - VoiceOver: オンのとき HUD の内容を一度だけ読み上げ
  - 性能の回帰テスト。正規表現の事前コンパイルと縮小処理の改善で、エラー検出・秘密情報検出・5K フレームの縮小を高速化
  - アプリアイコン、Developer ID 配布スクリプト（`scripts/release.sh`、[docs/RELEASE.md](docs/RELEASE.md)）
- **Movie / Anime モード（v0.9）**: YouTube・Netflix・Prime Video・Disney+・Crunchyroll・Hulu・U-NEXT・ABEMA・dアニメストア・Apple TV などをタイトル／URL から判定し、作品名と話数（「第5話」「S2E5」「Episode 3」）を解析
  - 新しい作品を見始めると 1 日 1 回 `DOSSIER // FEATURE`（年・原作・主要キャスト／声優・主題歌・あらすじ）。v0.11 から端末内の LLM の知識（有名作のみ）
  - 字幕やテロップにキャラクター名・演者名が出ると `CAST // ON SCREEN`（取得済みのキャストと端末内で照合、追加の通信なし）
  - **ネタバレ制御**: 0 完全禁止 / 1 現在地点以前（タイトルの話数まで）/ 2 軽度 / 3 制限なし（既定 1）
- **News モード（v0.9）**: ニュースサイトの記事を開くと `BRIEFING // BACKGROUND`。v0.11 からは端末内の LLM による一般的な背景と、過去 30 日に読んだ関連記事
- **商品・食品（v0.9）**: 識別対象に商品（ロゴはブランドとして）と料理を追加
- **識別と公人（v0.8 → v0.11 で端末内に移行）**
  - **動植物・ランドマーク**: `TARGET // IDENTIFICATION` に名前・学名や場所・3 つまでの補足。0.55 未満は表示しない
  - **公人（著名人）**: 顔が写っている画面で、字幕・キャプション・タイトルなど画面上の文字に出ている人名と周辺テキストから、公人であれば `DOSSIER // PUBLIC FIGURE` に肩書きと代表作を表示。顔から人物を特定することはしない。一般人と判定された場合や確度が低い場合は表示しない（判定結果は 30 日キャッシュ、同じ人は 1 日 1 回まで）
  - HUD の **WEB / WIKI** でブラウザの Google 検索・Wikipedia を開く（アプリ自身は通信しない）
- **作業コンテキスト（v0.7）**: 前面のページ（ブラウザは URL、ほかはアプリ＋ウィンドウタイトル）と閲覧時間を記録
  - **自動ブックマーク**: 閲覧時間・再訪・コピー・ポインタ滞在・HUD 表示から重要度を推定し、高いページを ★ で保存（保持期間を過ぎても残る）
  - **作業セッション**: Slack → Chrome → GitHub → VS Code → Terminal のような一連の作業を 1 つにまとめ、Apple Intelligence が名前を付ける（無ければキーワード）
  - **作業復元**: 起動時やスリープ復帰時、4 時間以上空いていたら 1 日 1 回「前回の続き」（ブックマークと主なページ）を表示
  - **TODAY**: Archive の TODAY タブに今日の主なテーマと時間、SESSIONS タブにセッション一覧
  - **ブラウザの URL**: Safari と Chromium 系（Chrome / Edge / Brave / Arc / Vivaldi）から Apple Events で取得。クエリ・フラグメント・認証情報は保存しない。macOS がブラウザごとに許可を求める
- **注目領域（v0.7）**: ポインタを 2 秒止めた領域を、画面が落ち着くのを待たずに優先して解析
- **QR コード（v0.7）**: 画面上の QR コードの行き先（ホスト＋パス）を `SCAN // QR PAYLOAD` で表示
- **Coding Mode（v0.6）**: VS Code・Xcode・ターミナル、またはブラウザで GitHub / GitLab / Stack Overflow を開いているときに切り替わる
  - **エラー解析**: Python / JavaScript / Swift / Rust / Go / Java / npm / git / シェルの代表的なエラーを検出し、Apple Intelligence が原因候補と次の一手を `ALERT // FAULT ANALYSIS` に表示。`0 errors`・警告・ビルド成功などの正常ログには反応しない
  - **コード説明**: ポインタを 2 秒止めた周辺のコードを読み取り、何をしているかを 1〜3 ステップで要約（`INTEL // CODE ANALYSIS`）
- **秘密情報の保護（v0.6）**: API キー（AWS / GitHub / Slack / Google / Stripe / LLM 各社）・秘密鍵・JWT・カード番号（Luhn 検証）・パスワード・メール・電話番号を端末内で検出。値は保存も表示もしない。含まれる文は翻訳・解説・記録の対象外
  - **画面共有中の警告**: Zoom / Meet / Teams などの共有インジケータから共有中を推定し、重要度の高い秘密情報が映ったら `⚠ WARNING // EXPOSURE RISK` を表示
  - **黒塗り（実験的、既定オフ）**: 共有中、検出した箇所を不透明な矩形で覆う
- **専門用語の解説（v0.5, Apple Intelligence）**: 略語（RAG・CRDT など）や長いカタカナ語を候補にし、説明する価値があるかと 2 行の説明を Foundation Models が判断・生成する（一般語・固有名詞は説明しない）。結果は 30 日キャッシュ。HUD の KNOWN か、3 回表示した用語は今後説明しない
- **LLM ルーター（v0.5, Apple Intelligence）**: ルールで判断が割れる候補（スコア 0.5〜0.7）だけをオンデバイス LLM に「今出す価値があるか」判定させる。8 秒に 1 回まで
- **再登場通知（v0.5）**: HUD に出した内容の固有名詞（NLTagger の人名・組織名・地名）や用語が 1 日以上前にも出ていたら `SEEN ▸ 3日前にも表示されています` を添える
- **SQLite 保存（v0.5）**: Visual Memory を GRDB の SQLite（全文検索は日本語も部分一致する FTS5 trigram）に移行。v0.4 の JSON は初回起動時に自動で取り込んで削除
- **HUD の More 操作（v0.5）**: HUD にポインタを 0.6 秒置くとカードだけがクリック可能になり、COPY / ARCHIVE（その翻訳で Archive を開く）/ NOT USEFUL / MUTE <言語> / ✕ を表示。ポインタを外すと 0.4 秒で元のクリック透過に戻る。キーボードの入力先は奪わない
- **Personalization の重み（v0.5）**: 仕様の比率どおり、閉じる −1 / More を開く +2 / コピー・Archive・検索 +3 / Not Useful −4（単位 0.03、上限 ±0.3）
- **Debug overlay（v0.5）**: 設定の Developer でオンにすると、変化領域・OCR 範囲・Router の候補とスコア・件数・各段の処理時間を画面に重ねる。認識テキストは出さない。Instruments の Points of Interest に `ocr` / `translate` 区間を記録。実機検証の手順は [docs/perf/CHECKLIST-v0.4.1.md](docs/perf/CHECKLIST-v0.4.1.md)
- **Visual Memory / Semantic Search（v0.4）**: HUD に表示した情報（原文・翻訳・BRIEF・アプリ・ウィンドウタイトル・言語・時刻）だけを記録し、⌥⌘K の「ARCHIVE」ウィンドウから自然言語で検索
  - 「昨日見ていたフランス語の美術館」「German train notice today」「さっきの英語」のような日付・言語の指定を解釈（`MemoryQueryParser`）
  - キーワード一致（日本語は 2 文字単位の部分一致）＋ NaturalLanguage のオンデバイス文埋め込みによる意味検索＋新しさで順位付け（`VisualMemoryIndex`）
  - 記録をクリックすると翻訳をコピーし、Personalization に「検索した（score ++）」として反映
  - 保存先はサンドボックス内の Application Support（JSON、バックアップ対象外）。保持期間 1 / 7 / 30 日（既定 7 日）、最大 1,000 件。設定とアーカイブ画面から全削除できる
- **SF スパイ映画風 HUD（v0.3）**: 画面全体を覆う透過・クリック透過レイヤーに描画
  - 対象テキストへのロックオン・レティクル（`ACQUIRING` → `LOCKED`）と、カードへ伸びる点線の引き出し線
  - ダークガラスのインテル・カード: `◢ INTERCEPT // LINGUISTIC` ヘッダ、ターゲットコード、`FR ▸ JA`、10 段の信頼度メーター、走査線、スキャンスイープ
  - 翻訳文は暗号が解読されるように表示（デコード演出、カードのサイズは変わらない）
  - 「視差効果を減らす」設定時はアニメーションを省略。演出が終わるとタイムラインを止めて CPU を使わない
- **Briefing（v0.3, macOS 26 + Apple Intelligence）**: Foundation Models のオンデバイス LLM で、翻訳に一行の補足（`BRIEF ▸ …`）を付ける。HUD は先に表示し、生成中は `ANALYZING ▮`。5 秒でタイムアウト。LLM に渡すのは認識済みのテキストとアプリ名だけで、画像は渡さない
- **HUD の配置（v0.2）**: 対象テキストの近く（下 → 上 → 右 → 左の順で、文字を隠さず画面内に収まる位置）に表示。設定で右上固定にも切替可能
- **複数ディスプレイ（v0.2）**: 「マウスポインタのあるディスプレイを追従」をオンにすると、ポインタの移動に合わせてキャプチャ対象のディスプレイを切り替え（2 秒ごとに確認）。HUD はキャプチャ中のディスプレイに表示
- **Personalization（v0.2）**: HUD はクリック透過のまま、ポインタを 0.6 秒以上乗せると「関心あり」として加点し、乗せている間は消えない。メニューの *Not Useful* で減点。学習するのは「アクション × 言語 × アプリ」単位の重みだけで、テキストは保存しない（`PersonalizationModel`、上限 ±0.3）。設定画面からリセット可能
- **Pause / Resume**: 5 分・30 分・無期限。停止中はキャプチャ自体を止める
- **Privacy**: 除外アプリ（1Password などのパスワードマネージャー、メッセージ、写真）とパスワード系ウィンドウタイトルでは解析しない
- **Performance Mode**: Battery / Balanced / Performance（キャプチャ 5/15/30fps、Vision 0.5/1/2fps）
- **Unit Test**: ChangeDetector、AnalysisScheduler、ForeignTextDetector、AIRouter、InterestScore、Cooldown、TextBlockGrouper、PrivacyPolicy 、HUDPlacement、Personalization、DecodeEffect、Briefing、VisualMemory、PauseSchedule、Diagnostics、TermExtractor、IntelStore、ErrorDetector、SensitiveDataDetector、WorkSessionClusterer、BookmarkScorer、IdentificationPolicy、MediaTitleParser、NewsDetector、Onboarding、UnitConverter、AcronymGlossary、ErrorHints、VisualLabelSelector、CircleGestureRecognizer、ActiveLookupPlanner、FeatureSettings、AIAnswerRecord、TimeConverter、ArchiveQuestion、IntelSource、CronExplainer、StackTraceAnalyzer、DictionaryDefinition、ScreenSummary、マイナンバー、性能の回帰テストなど（うちストア 16 件は macOS のみ）

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
- 翻訳には、事前に翻訳言語モデルのダウンロードが必要です
- macOS 15 の翻訳は SwiftUI `.translationTask` を 1×1 の透明ウィンドウでホストする方式のため、環境によっては動作しない可能性があります（8 秒でタイムアウトし、何も表示しません）。macOS 26 では直接 `TranslationSession` を使います
- 起動時点ですでに表示されている内容は解析しません（変化した部分だけが対象）
- 端末内の LLM は画像を見られず、知識も学習時点までです。識別・公人・作品・ニュースの補足は分類ラベルと画面上の文字からの推定で、外れることがあります（新しい作品・最近のニュースは分かりません）。Apple Intelligence（macOS 26）が無い Mac では、これらは表示されません
- 除外アプリの「キャプチャ画像からの除去」は解析開始時点で起動中のアプリが対象です（後から起動したアプリも、前面にある間は解析しません）
- Briefing は macOS 26 かつ Apple Intelligence が有効な Mac でのみ動作します（それ以外では行ごと表示されません）
- HUD は通常クリック透過です。カードにポインタを置くと More 操作が開き、✕ で閉じたり *Not Useful* を選んだりできます
- WEB / WIKI はブラウザで検索ページを開きます。アプリは通信しないため、Web 検索結果をアプリ内に取り込むことはできません
- 略語の用語集はメモリ上だけにあり、アプリを終了すると消えます
- 開発環境の都合上、本リポジトリの初期実装は Linux 上でコアロジックのビルドとテストのみ検証しています。アプリ本体のビルドは GitHub Actions（macOS ランナー）で確認しています

## 開発履歴と次の段階

詳細は [docs/ROADMAP.md](docs/ROADMAP.md)。

| # | リリース | テーマ |
| --- | --- | --- |
| M0 | v0.4.1 | 実機検証と安定化（最優先） |
| M1 | v0.5 | SQLite 移行、HUD の More 操作、専門用語の解説、再登場通知、LLM ルーター |
| M2 | v0.6 | Coding Mode（エラー解析・コード説明）、秘密情報検出、画面共有中の警告 |
| M3 | v0.7 | マウス注目領域、自動ブックマーク、作業セッション、作業復元 |
| M4 | v0.8 | クラウド AI（オプトイン）、動植物・ランドマーク識別（v0.11 で端末内に置き換え） |
| M5 | v0.9 | Movie / Anime / News モード |
| — | v0.10 | 製品化の候補（ガイド・日本語・VoiceOver・性能テスト・配布準備） |
| M6 | v0.11〜 | ローカル AI の拡張（クラウド撤去、端末内の推定、AI なしで動く略語・単位・エラーのヒント） |
| — | v1.0 | 実機チェックリストを通したもの |

## Privacy policy（概要）

- **Local Only**: OCR・言語判定・翻訳・画像分類・LLM による説明と推定はすべて Mac 上で実行します。アプリはネットワークに接続しません（ネットワークの Entitlement を持ちません）
- **保存しない**: 画面キャプチャはメモリ上でのみ扱い、ディスクに保存しません。前フレームは 320px の輝度サムネイルだけを保持します
- **Visual Memory と閲覧記録**: 認識テキストは HUD に実際に表示したものだけを記録します。閲覧記録が有効な場合は、ページのタイトル・サニタイズ済み URL・閲覧時間も保存します。画像は保存しません。保存先はこの Mac のアプリ専用領域の SQLite データベースで、バックアップ対象外です。設定でオフにでき、いつでも全削除できます
- **送信しない**: v0.10 までのオプトインの Gemini 連携は v0.11 で削除しました。以前に保存した API キーは起動時にキーチェーンから削除します
- **除外**: パスワードマネージャー、メッセージ、写真などはキャプチャ画像から除去され、解析もされません。パスワード入力画面らしいウィンドウタイトルでも解析を止めます。除外アプリは設定画面で追加できます
- **ログ**: OCR したテキストの本文はログに記録しません（件数・文字数・言語コードのみ）
- **保存される設定**: 翻訳先言語・モード・除外アプリなどの設定値と、Personalization の重み（アクション・言語・アプリ ID ごとの数値のみ）を `UserDefaults` に保存します
