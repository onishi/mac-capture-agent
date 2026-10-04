import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A word that might be a technical term worth explaining.
public struct TermCandidate: Sendable, Equatable {
    public let term: String
    public let canonical: String
    /// The surrounding text (truncated), given to the model for disambiguation.
    public let context: String
    /// Normalized, top-left-origin rect of the text block containing it.
    public let region: CGRect?

    public init(term: String, context: String, region: CGRect?) {
        self.term = term
        self.canonical = EntityName.canonical(term)
        self.context = context
        self.region = region
    }
}

/// Finds technical-term candidates with cheap rules: acronyms (RAG, LLM, CRDT)
/// and long katakana compounds (ファインチューニング). Common words are excluded.
/// Whether a candidate is actually worth explaining is decided later (LLM).
public struct TermExtractor: Sendable {
    public var maximumPerBlock = 3
    public var contextLength = 240

    /// Acronyms everyone knows; never explained.
    public static let commonAcronyms: Set<String> = [
        "OK", "AI", "API", "URL", "PDF", "USB", "CEO", "CTO", "CFO", "FAQ", "PC", "TV", "US", "USA", "UK", "EU", "UN",
        "JP", "ID", "IT", "PR", "HR", "AM", "PM", "KB", "MB", "GB", "TB", "HD", "SNS", "DVD", "CD", "GPS", "WIFI",
        "HTML", "CSS", "HTTP", "HTTPS", "WWW", "JSON", "XML", "SQL", "IOS", "MAC", "APP", "NEW", "FREE", "SALE",
        "NG", "OS", "CPU", "GPU", "RAM", "SSD", "LED", "LCD", "DM", "QA", "VS", "ETC", "NO", "NG", "PS", "FYI",
        "ASAP", "TBD", "NHK", "JR", "COVID", "LGBT", "SDGS", "DX", "IOT", "VR", "AR", "UI", "UX", "EC"
    ]

    /// Katakana loanwords common enough to never explain.
    public static let commonKatakana: Set<String> = [
        "コンピューター", "コンピュータ", "インターネット", "ダウンロード", "アップロード", "アップデート", "メッセージ",
        "サービス", "ユーザー", "ログイン", "ログアウト", "パスワード", "アカウント", "メールアドレス", "ホームページ",
        "スマートフォン", "アプリケーション", "ソフトウェア", "ハードウェア", "キーボード", "ディスプレイ", "プログラム",
        "データベース", "ネットワーク", "セキュリティ", "プライバシー", "ニュース", "コメント", "コンテンツ", "カテゴリー",
        "ランキング", "キャンペーン", "プレゼント", "ショッピング", "レストラン", "スケジュール", "カレンダー", "フォロワー",
        "チャンネル", "プロフィール", "ブックマーク", "クリック", "スクロール", "ウィンドウ", "メニュー", "ボタン"
    ]

    public init() {}

    public func candidates(in regions: [RecognizedTextRegion]) -> [TermCandidate] {
        var seen = Set<String>()
        var result: [TermCandidate] = []
        for region in regions {
            let context = String(TextHeuristics.normalized(region.text).prefix(contextLength))
            var found = 0
            for term in terms(in: region.text) where found < maximumPerBlock {
                let candidate = TermCandidate(term: term, context: context, region: region.boundingBox)
                guard !seen.contains(candidate.canonical) else { continue }
                seen.insert(candidate.canonical)
                result.append(candidate)
                found += 1
            }
        }
        return result
    }

    /// Candidate terms in reading order.
    public func terms(in text: String) -> [String] {
        var result: [String] = []
        for token in tokens(in: text) {
            if isAcronym(token) || isKatakanaCompound(token) {
                if !result.contains(token) { result.append(token) }
            }
        }
        return result
    }

    private func tokens(in text: String) -> [String] {
        // Split on anything that is not a letter, digit, katakana prolonged mark or middle dot.
        var tokens: [String] = []
        var current = ""
        var currentIsKatakana: Bool?
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
            currentIsKatakana = nil
        }
        for character in text {
            let katakana = Self.isKatakana(character)
            let latin = character.isASCII && (character.isLetter || character.isNumber)
            guard katakana || latin else { flush(); continue }
            if let kind = currentIsKatakana, kind != katakana { flush() }
            currentIsKatakana = katakana
            current.append(character)
        }
        flush()
        return tokens
    }

    func isAcronym(_ token: String) -> Bool {
        var core = token
        if core.count > 2, core.hasSuffix("s"), core.dropLast().allSatisfy({ $0.isUppercase || $0.isNumber }) {
            core = String(core.dropLast())   // plural: LLMs
        }
        guard (2...6).contains(core.count),
              core.allSatisfy({ ($0.isUppercase && $0.isLetter) || $0.isNumber }),
              core.filter(\.isLetter).count >= 2,
              core.first?.isLetter == true
        else { return false }
        if Self.isRomanNumeral(core) { return false }
        return !Self.commonAcronyms.contains(core.uppercased())
    }

    func isKatakanaCompound(_ token: String) -> Bool {
        guard token.count >= 6, token.allSatisfy(Self.isKatakana) else { return false }
        return !Self.commonKatakana.contains(token)
    }

    static func isKatakana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return (0x30A1...0x30FA).contains(scalar.value) || scalar.value == 0x30FC || scalar.value == 0x30FB
    }

    /// A well-formed Roman numeral (IV, XII, MCMXC), not just Roman letters (LLM).
    static func isRomanNumeral(_ token: String) -> Bool {
        guard !token.isEmpty else { return false }
        return token.range(of: "^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$", options: .regularExpression) != nil
    }
}
