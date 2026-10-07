import Foundation

/// Canned causes and next steps for common errors, used when the on-device
/// model is unavailable or gives nothing usable (SPEC LA-20). Rules only.
public enum ErrorHints {
    private struct Hint {
        let pattern: CompiledPattern
        /// Text per language ("ja", "en"); `$1` is replaced with the first capture group that matched.
        let cause: [String: String]
        let fix: [String: String]
    }

    private static func hint(_ regex: String, ja: (String, String), en: (String, String)) -> Hint {
        Hint(pattern: CompiledPattern(regex), cause: ["ja": ja.0, "en": en.0], fix: ["ja": ja.1, "en": en.1])
    }

    /// Ordered from most to least specific.
    private static let hints: [Hint] = [
        hint(#"ModuleNotFoundError: No module named '([\w.\-]+)'"#,
             ja: ("Python モジュール $1 がこの環境にインストールされていません", "仮想環境を確認し pip install $1"),
             en: ("The Python module $1 is not installed in this environment", "Check the virtualenv, then pip install $1")),
        hint(#"Cannot find module '([^']+)'"#,
             ja: ("Node.js がモジュール $1 を見つけられません", "npm install を実行するか、パスの綴りを確認"),
             en: ("Node.js cannot find the module $1", "Run npm install or check the import path")),
        hint(#"EADDRINUSE.*?:(\d+)"#,
             ja: ("ポート $1 は別のプロセスが使用中です", "lsof -i :$1 で使用中のプロセスを確認して止める"),
             en: ("Port $1 is already in use by another process", "Find it with lsof -i :$1 and stop it")),
        hint(#"ECONNREFUSED"#,
             ja: ("接続先のサーバーが起動していないか、ポートが違います", "接続先のサービスが起動しているか確認"),
             en: ("Nothing is listening at the address (server down or wrong port)", "Check that the service is running")),
        hint(#"TypeError: Cannot read propert(?:y|ies) of (undefined|null)"#,
             ja: ("$1 の値に対してプロパティを読もうとしています", "直前で値が設定されているか、?. で保護する"),
             en: ("A property is read from a value that is $1", "Check the value is set first, or use ?.")),
        hint(#"(?:is not a function)"#,
             ja: ("関数ではない値を呼び出しています（名前の誤り・import の誤りなど）", "呼び出している名前と import を確認"),
             en: ("Something that is not a function is being called (typo or wrong import)", "Check the name and the import")),
        hint(#"NameError: name '(\w+)' is not defined"#,
             ja: ("$1 が定義される前に使われています（綴り・import 漏れ）", "綴りと import を確認"),
             en: ("$1 is used before it is defined (typo or missing import)", "Check the spelling and imports")),
        hint(#"IndentationError|TabError"#,
             ja: ("インデントが揃っていません（タブとスペースの混在など）", "エディタでインデントをスペースに統一"),
             en: ("Inconsistent indentation (tabs and spaces mixed)", "Convert indentation to spaces")),
        hint(#"SyntaxError"#,
             ja: ("構文が正しくありません（括弧・引用符・カンマの閉じ忘れなど）", "示された行とその直前の行を確認"),
             en: ("The code does not parse (unclosed bracket, quote or comma)", "Check the reported line and the one before")),
        hint(#"KeyError: '?([^']+)'?"#,
             ja: ("辞書にキー $1 がありません", "キーの有無を確認するか .get() を使う"),
             en: ("The key $1 is not in the dictionary", "Check the key exists or use .get()")),
        hint(#"Unexpectedly found nil while unwrapping"#,
             ja: ("nil の Optional を強制アンラップしています", "if let / guard let で安全に取り出す"),
             en: ("A nil Optional was force-unwrapped", "Unwrap safely with if let / guard let")),
        hint(#"Index out of range|IndexError|index out of bounds"#,
             ja: ("配列の範囲外の要素にアクセスしています", "要素数とループの範囲を確認"),
             en: ("An element outside the array is accessed", "Check the count and the loop bounds")),
        // zsh: "zsh: command not found: pnpm" (checked first: the bash form would capture "zsh").
        hint(#"command not found: (\S+)"#,
             ja: ("コマンド $1 が見つかりません（未インストールか PATH にない）", "インストールするか PATH を確認"),
             en: ("The command $1 is not found (not installed or not on PATH)", "Install it or check PATH")),
        // bash: "bash: pnpm: command not found".
        hint(#"([^\s:]+): command not found"#,
             ja: ("コマンド $1 が見つかりません（未インストールか PATH にない）", "インストールするか PATH を確認"),
             en: ("The command $1 is not found (not installed or not on PATH)", "Install it or check PATH")),
        hint(#"Permission denied \(publickey\)"#,
             ja: ("SSH 鍵が登録されていないか、使われていません", "ssh -T で接続を確認し、鍵を登録"),
             en: ("The SSH key is not registered or not offered", "Test with ssh -T and register the key")),
        hint(#"Permission denied"#,
             ja: ("ファイルやディレクトリへの権限がありません", "所有者と権限（ls -l）を確認"),
             en: ("No permission for the file or directory", "Check owner and mode with ls -l")),
        hint(#"No such file or directory"#,
             ja: ("指定したパスにファイルがありません", "カレントディレクトリとパスの綴りを確認"),
             en: ("Nothing exists at the given path", "Check the working directory and the path")),
        hint(#"CONFLICT \(content\)|Automatic merge failed"#,
             ja: ("マージで同じ箇所が両方で変更されています", "競合マーカーを解消して git add → commit"),
             en: ("Both sides changed the same lines", "Resolve the conflict markers, then git add and commit")),
        hint(#"rejected.*\(non-fast-forward\)|Updates were rejected"#,
             ja: ("リモートに手元にないコミットがあります", "git pull（または fetch と merge）してから push"),
             en: ("The remote has commits you don't have", "Pull (or fetch and merge) before pushing")),
        hint(#"not a git repository"#,
             ja: ("Git リポジトリの外でコマンドを実行しています", "リポジトリのディレクトリに移動"),
             en: ("The command runs outside a Git repository", "cd into the repository")),
        hint(#"npm ERR! code ERESOLVE"#,
             ja: ("依存パッケージのバージョンが衝突しています", "衝突しているパッケージを揃えるか --legacy-peer-deps を検討"),
             en: ("Dependency versions conflict", "Align the versions or consider --legacy-peer-deps")),
        hint(#"Segmentation fault"#,
             ja: ("不正なメモリアクセスでプロセスが落ちました", "直前に呼んだネイティブ処理や拡張を確認"),
             en: ("The process crashed on an invalid memory access", "Check the native code or extension called last")),
        hint(#"out of memory|OutOfMemoryError|heap out of memory"#,
             ja: ("メモリが足りなくなりました", "データ量を減らすかメモリ上限を上げる"),
             en: ("The process ran out of memory", "Reduce the data or raise the memory limit")),
        hint(#"cannot find '(\w+)' in scope"#,
             ja: ("$1 がこのスコープにありません（綴り・import・アクセス修飾子）", "宣言の場所と import を確認"),
             en: ("$1 is not visible here (typo, import or access level)", "Check the declaration and imports")),
        hint(#"timed? ?out|ETIMEDOUT"#,
             ja: ("応答が時間内に返りませんでした", "接続先の状態とネットワークを確認"),
             en: ("No response in time", "Check the remote side and the network"))
    ]

    /// A canned explanation for the error line, or nil when no rule applies.
    public static func hint(for line: String, targetLanguage: String) -> ErrorExplanation? {
        let language = LanguageCode.base(targetLanguage) == "ja" ? "ja" : "en"
        for hint in hints {
            guard let groups = hint.pattern.captures(in: line).first else { continue }
            // The first group that took part (patterns may have alternatives).
            let capture = groups.dropFirst().compactMap { $0 }.first ?? ""
            guard let cause = hint.cause[language], let fix = hint.fix[language] else { continue }
            return ErrorExplanation(
                cause: cause.replacingOccurrences(of: "$1", with: capture),
                fix: fix.replacingOccurrences(of: "$1", with: capture)
            )
        }
        return nil
    }
}
