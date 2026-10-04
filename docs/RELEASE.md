# リリース手順

Developer ID 署名＋公証の DMG を作る手順。配布方法は [ROADMAP.md](ROADMAP.md) の判断事項 D-6 で決める（推奨は Developer ID）。Mac App Store を選ぶ場合、Apple Events の一時的例外 Entitlement（ブラウザ URL の取得）は審査で認められない可能性が高く、別の取得方法が必要になる。

## 1. 事前準備（初回のみ）

1. Apple Developer Program に登録し、Team ID を確認する
2. Xcode › Settings › Accounts でアカウントを追加し、**Developer ID Application** 証明書を作る
3. 公証用の認証情報をキーチェーンに保存する（App 用パスワードは appleid.apple.com で発行）
   ```sh
   xcrun notarytool store-credentials ambient --apple-id <Apple ID> --team-id <TEAM_ID>
   ```

## 2. バージョンを上げる

`AmbientScreenIntelligence.xcodeproj/project.pbxproj` の `MARKETING_VERSION`（表示用）と `CURRENT_PROJECT_VERSION`（ビルド番号、毎回増やす）を両方の構成で更新する。

## 3. 文字列とアイコン

ユーザー向けの文言を変えたら:

```sh
python3 scripts/make_strings.py   # Localizable.xcstrings（英語キー＋日本語訳）
python3 scripts/make_icon.py      # AppIcon（Pillow が必要）
```

## 4. ビルド・公証・DMG

```sh
TEAM_ID=ABCDE12345 NOTARY_PROFILE=ambient ./scripts/release.sh
```

スクリプトの内容:

1. `swift test`
2. Release 構成でアーカイブ（Hardened Runtime は有効済み）
3. `Config/ExportOptions.plist`（method = developer-id）でエクスポート
4. `codesign --verify --deep --strict`
5. DMG を作成して署名
6. `notarytool submit --wait` で公証
7. `stapler staple` と `spctl --assess` で確認

成果物は `build/release/AmbientScreenIntelligence-<version>.dmg`（`build/` は Git の対象外）。

## 5. 公開前の確認

- [ROADMAP.md](ROADMAP.md) §5 の実機チェックリストをすべて通す
- 別の Mac（開発環境のないユーザーアカウント）で DMG を開き、Gatekeeper の警告なしに起動できる
- 画面収録の許可 → 再起動 → `Running` まで、ガイドどおりに進める
- 初回起動時と Gemini オフの状態で通信が発生しないこと（docs/ の通信確認手順）

## 注意

- 署名した Team を変えると、画面収録の許可は取り直しになる
- Entitlement（`Config/AmbientScreenIntelligence.entitlements`）を変更する場合は ROADMAP の判断事項を先に確認する
