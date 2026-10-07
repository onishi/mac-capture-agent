#!/usr/bin/env python3
"""Generates Sources/AmbientApp/Resources/Localizable.xcstrings (en source, ja).

Keys are the English strings used in the code. Interpolated values become
%@ (strings) or %lld (integers), as Xcode extracts them. HUD chrome
(codenames, "INTEL", status words in the spy style) stays English on purpose.
Run after changing user-facing strings: python3 scripts/make_strings.py
"""
import json
import pathlib

JA = {
    # Menu bar
    "Stopped": "停止中",
    "Starting…": "起動中…",
    "Running": "稼働中",
    "Paused": "一時停止中",
    "Paused until %@": "%@ まで一時停止",
    "Paused until tomorrow %@": "明日 %@ まで一時停止",
    "Screen Recording permission required": "画面収録の許可が必要です",
    "Error: %@": "エラー: %@",
    "Pause 5 Minutes": "5 分間一時停止",
    "Pause 30 Minutes": "30 分間一時停止",
    "Pause Until Tomorrow": "明日まで一時停止",
    "Pause": "一時停止",
    "Resume": "再開",
    "Grant Screen Recording Permission…": "画面収録を許可…",
    "Retry": "再試行",
    "Last: %@": "直前: %@",
    "Not Useful": "役に立たなかった",
    "Stop Translating %@": "%@ を翻訳しない",
    "Translation Languages…": "翻訳言語…",
    "Archive…": "アーカイブ…",
    "Preview HUD": "HUD をプレビュー",
    "Settings…": "設定…",
    "Welcome Guide…": "ようこそガイド…",
    "Quit Ambient Screen Intelligence": "Ambient Screen Intelligence を終了",
    # Settings
    "Translation": "翻訳",
    "Translate into": "翻訳先",
    "I read English — don't translate it": "英語は読めるので翻訳しない",
    "Not translated: %@": "翻訳しない: %@",
    "Translation runs on-device. Install language models in System Settings › General › Language & Region › Translation Languages.":
        "翻訳はこの Mac 上で行います。言語モデルは「システム設定 › 一般 › 言語と地域 › 翻訳言語」でダウンロードしてください。",
    "Analysis": "解析",
    "Mode": "モード",
    "Battery": "省電力",
    "Balanced": "標準",
    "Performance": "高性能",
    "Classify images (experimental)": "画像を分類する（実験的）",
    "Follow the display under the mouse pointer": "マウスポインタのあるディスプレイを追う",
    "Intelligence": "インテリジェンス",
    "Briefing notes (Apple Intelligence, on-device)": "ひとことメモ（Apple Intelligence・端末内）",
    "Explain technical terms and judge borderline text": "専門用語の解説と、迷う候補の判定",
    "Adds a one-line note about what the text means for you. Runs entirely on this Mac.":
        "その内容があなたにとって何を意味するかを 1 行で添えます。すべてこの Mac 上で動きます。",
    "Requires macOS 26 with Apple Intelligence turned on.": "macOS 26 で Apple Intelligence をオンにする必要があります。",
    "Visual memory": "ビジュアルメモリ",
    "Archive intel shown in the HUD": "HUD に表示した情報を記録する",
    "Remember pages you read (titles, URLs, reading time)": "読んだページを記録する（タイトル・URL・閲覧時間）",
    "Read the URL of the front browser tab": "最前面のブラウザタブの URL を読む",
    "Offer to pick up where you left off": "前回の続きを提案する",
    "Keep for": "保存期間",
    "1 day": "1 日",
    "%lld days": "%lld 日",
    "Archived: text shown in the HUD, and — if enabled — titles, URLs (without query strings) and reading time of pages, for automatic bookmarks and work sessions. Never screenshots. On this Mac only; excluded apps are never recorded. Search with ⌥⌘K. macOS asks once per browser before URLs can be read.":
        "記録するのは HUD に表示したテキストと、（オンの場合）自動ブックマークと作業セッションのためのページのタイトル・URL（クエリ文字列なし）・閲覧時間です。スクリーンショットは保存しません。この Mac の中だけに保存し、除外アプリは記録しません。⌥⌘K で検索できます。URL を読む前に、ブラウザごとに一度 macOS が確認します。",
    "Purge Archive": "アーカイブを消去",
    "HUD": "HUD",
    "Position": "位置",
    "Near the text": "テキストの近く",
    "Top right corner": "右上",
    "Hovering the HUD keeps it on screen and tells the app the information was useful. Use “Not Useful” in the menu bar to see less of something.":
        "HUD にポインタを乗せると表示が続き、役に立ったことがアプリに伝わります。表示を減らしたいものは、メニューバーの「役に立たなかった」を使ってください。",
    "Reset Learned Preferences": "学習した好みをリセット",
    "Excluded apps": "除外アプリ",
    "Bundle identifier (e.g. com.example.app)": "バンドル ID（例: com.example.app）",
    "Add": "追加",
    "Excluded apps are removed from the captured image and never analyzed.": "除外アプリはキャプチャ画像から取り除かれ、解析されません。",
    "Developer": "開発者向け",
    "Debug overlay": "デバッグ表示",
    "Pretend the screen is being shared": "画面共有中として扱う",
    "Draws changed regions, OCR areas, router scores, counters and timings on screen. Never shows recognized text.":
        "変化領域・OCR 範囲・ルーターのスコア・件数・処理時間を画面に描きます。認識したテキストは表示しません。",
    "On-device knowledge": "端末内の知識",
    "Identify animals, plants, landmarks, dishes and products (estimate)": "動植物・ランドマーク・料理・製品を推定する",
    "Identify public figures named on screen": "画面に名前が出ている著名人を推定する",
    "Convert miles, °F, pounds… where the pointer rests": "ポインタを置いたところのマイル・°F・ポンドなどを換算する",
    "Everything runs on this Mac; the app never sends anything over the network. The on-device model cannot see images — it guesses from image labels and nearby text, so names are marked “possibly” unless the screen shows them. Abbreviations defined on screen and common errors are explained even without Apple Intelligence.":
        "すべてこの Mac の中で動き、ネットワークには何も送りません。端末内のモデルは画像を見られないため、画像の分類ラベルと周辺の文字から推定します。画面に名前が出ていない限り「かもしれません」と表示します。画面で定義された略語とよくあるエラーは、Apple Intelligence がなくても説明します。",
    "Movie, anime & news": "映画・アニメ・ニュース",
    "Movie / Anime mode (work card, cast on screen)": "映画・アニメモード（作品カード、画面上のキャスト）",
    "Spoilers": "ネタバレ",
    "0 — No spoilers": "0 — ネタバレなし",
    "1 — Up to where I am": "1 — 見ているところまで",
    "2 — Light": "2 — 軽め",
    "3 — Unrestricted": "3 — 制限なし",
    "News mode (background of the story)": "ニュースモード（ニュースの背景）",
    "Work cards and news backgrounds come from the on-device model’s own knowledge (well-known works only; it does not know recent news). News mode also lists related pages you read earlier. Both need “Remember pages you read”. “Up to where I am” uses the episode number in the title; without one it behaves like “No spoilers”.":
        "作品カードとニュースの背景は、端末内のモデルが持つ知識から作ります（有名な作品のみ。最近のニュースは知りません）。ニュースモードでは以前に読んだ関連ページも表示します。どちらも「読んだページを記録する」が必要です。「見ているところまで」はタイトルの話数を使い、話数がなければ「ネタバレなし」と同じ動作になります。",
    "Screen sharing": "画面共有",
    "Warn about secrets while sharing the screen": "画面共有中に秘密情報を警告する",
    "Cover secrets while sharing (experimental)": "画面共有中に秘密情報を隠す（実験的）",
    "API keys, private keys, tokens, card numbers and passwords are detected on-device. Their values are never stored or shown. Text containing them is never translated or archived.":
        "API キー・秘密鍵・トークン・カード番号・パスワードを端末内で検出します。値そのものは保存も表示もしません。それらを含むテキストは翻訳も記録もしません。",
    "Privacy": "プライバシー",
    "Screen content is processed in memory on this Mac. Screen images are never saved. Nothing is ever sent over the network.":
        "画面の内容はこの Mac のメモリ上で処理します。画面画像は保存しません。ネットワークには何も送りません。",
    # Onboarding
    "◢ FIELD MANUAL": "◢ FIELD MANUAL",
    "Briefing": "概要",
    "Screen access": "画面へのアクセス",
    "Apple Intelligence": "Apple Intelligence",
    "Ambient Screen Intelligence watches your screen with you and quietly adds what you would have searched for — a translation, a term, the cause of an error, who is on screen.":
        "Ambient Screen Intelligence はあなたと一緒に画面を見て、調べようとしていたこと — 翻訳、用語、エラーの原因、画面に映っている人 — をそっと補足します。",
    "It prefers to show nothing. Most of the time you will not notice it; a card appears only when it is likely to be worth it, and fades after a few seconds.":
        "基本は何も表示しません。ほとんどの時間は存在に気づかないはずです。役に立ちそうなときだけカードが現れ、数秒で消えます。",
    "Hover a card to keep it and to open its actions. ⌥⌘K opens the archive of everything it has shown you.":
        "カードにポインタを乗せると表示が続き、操作ボタンが使えます。⌥⌘K でこれまでに表示した内容のアーカイブを開けます。",
    "To see what you see, the app needs Screen Recording permission. Frames stay in memory and are never saved or uploaded.":
        "あなたと同じ画面を見るために、画面収録の許可が必要です。フレームはメモリ上だけで扱い、保存もアップロードもしません。",
    "Open Screen Recording settings": "画面収録の設定を開く",
    "After enabling the app in System Settings, quit and reopen it.": "システム設定でこのアプリをオンにしたら、一度終了して開き直してください。",
    "Translation runs on this Mac with Apple's Translation models. Download the languages you want translated in System Settings › General › Language & Region › Translation Languages.":
        "翻訳は Apple の翻訳モデルを使ってこの Mac 上で行います。翻訳したい言語を「システム設定 › 一般 › 言語と地域 › 翻訳言語」でダウンロードしてください。",
    "Open Translation Languages": "翻訳言語を開く",
    "With Apple Intelligence (macOS 26), the app also explains technical terms, errors and code, adds one-line briefings, names your work sessions and filters borderline cards — all on-device.":
        "Apple Intelligence（macOS 26）があれば、専門用語・エラー・コードの解説、ひとことメモ、作業セッションの命名、迷うカードの判定も行います。すべて端末内で動きます。",
    "Open Apple Intelligence settings": "Apple Intelligence の設定を開く",
    "Everything else works without it.": "それ以外の機能は Apple Intelligence なしで使えます。",
    "Everything happens on this Mac. The app has no cloud features and never sends screen content anywhere.":
        "すべてこの Mac の中で行います。クラウドの機能はなく、画面の内容をどこにも送りません。",
    "With Apple Intelligence it also guesses what an animal, plant, landmark, dish or product is, who a public figure named on screen is, which film you are watching and the background of a news story. The on-device model cannot see images and knows nothing recent, so these are estimates marked “possibly”.":
        "Apple Intelligence があれば、動植物・ランドマーク・料理・製品が何か、画面に名前が出ている著名人が誰か、見ている作品、ニュースの背景も推定します。端末内のモデルは画像を見られず最近の出来事も知らないため、これらは「かもしれません」付きの推定です。",
    "Without it, the app still converts units where the pointer rests, expands abbreviations defined earlier on screen and gives hints for common errors.":
        "Apple Intelligence がなくても、ポインタを置いたところの単位換算、以前に画面で定義された略語の展開、よくあるエラーのヒントは使えます。",
    "Open Settings": "設定を開く",
    "• Screen images are never written to disk.": "• 画面画像はディスクに保存しません。",
    "• Only what a card showed, plus page titles and URLs (if enabled), is archived — on this Mac, excluded from backups, deletable at any time.":
        "• 記録するのはカードに表示した内容と、（オンの場合）ページのタイトルと URL だけです。この Mac の中に保存し、バックアップから除外され、いつでも消去できます。",
    "• Password managers, Messages and Photos are excluded; you can add more apps.": "• パスワード管理アプリ・メッセージ・写真は除外済みです。除外するアプリは追加できます。",
    "• Pause any time from the menu bar, for 5 minutes, 30 minutes or until tomorrow.": "• メニューバーからいつでも一時停止できます（5 分・30 分・明日まで）。",
    "Screen Recording permission is required to start.": "開始するには画面収録の許可が必要です。",
    "Next": "次へ",
    "Start": "開始",
    "PERMISSION GRANTED": "許可済み",
    "PERMISSION REQUIRED": "許可が必要",
    "APPLE INTELLIGENCE AVAILABLE": "APPLE INTELLIGENCE 利用可能",
    "NOT AVAILABLE ON THIS MAC": "この MAC では利用不可",
    "ON-DEVICE KNOWLEDGE READY": "端末内の知識: 利用可能",
    "RULES ONLY (NO APPLE INTELLIGENCE)": "ルールのみ（APPLE INTELLIGENCE なし）",
    # VoiceOver
    "Ambient Screen Intelligence: %@. %@": "Ambient Screen Intelligence: %@。%@",
}


def main() -> None:
    strings = {}
    for key in sorted(JA):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {"ja": {"stringUnit": {"state": "translated", "value": JA[key]}}},
        }
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    out = pathlib.Path(__file__).resolve().parent.parent / "Sources/AmbientApp/Resources/Localizable.xcstrings"
    out.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {len(strings)} strings to {out}")


if __name__ == "__main__":
    main()
