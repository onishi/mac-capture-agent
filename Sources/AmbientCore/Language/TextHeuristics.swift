import Foundation

/// Cheap, language independent statistics about a piece of text.
public struct TextHeuristics: Sendable, Equatable {
    public let letterCount: Int
    public let cjkCount: Int
    public let digitCount: Int
    public let wordCount: Int
    public let characterCount: Int

    public init(_ text: String) {
        var letters = 0, cjk = 0, digits = 0, characters = 0
        for scalar in text.unicodeScalars where !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            characters += 1
            if TextHeuristics.isCJK(scalar) {
                cjk += 1
                letters += 1
            } else if CharacterSet.letters.contains(scalar) {
                letters += 1
            } else if CharacterSet.decimalDigits.contains(scalar) {
                digits += 1
            }
        }
        letterCount = letters
        cjkCount = cjk
        digitCount = digits
        characterCount = characters
        wordCount = text.split(whereSeparator: { $0.isWhitespace }).filter { $0.contains(where: \.isLetter) }.count
    }

    /// Fraction of non-whitespace characters that are letters.
    public var letterRatio: Double {
        characterCount == 0 ? 0 : Double(letterCount) / Double(characterCount)
    }

    public static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF,   // Hiragana, Katakana
             0x3400...0x4DBF,   // CJK Extension A
             0x4E00...0x9FFF,   // CJK Unified Ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0x1100...0x11FF,   // Hangul Jamo
             0xF900...0xFAFF,   // CJK Compatibility Ideographs
             0xFF66...0xFF9D:   // Half-width Katakana
            return true
        default:
            return false
        }
    }

    /// URLs, e-mail addresses, file paths and code snippets are not prose worth translating.
    public static func looksLikeCodeOrIdentifier(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("://") || lowered.hasPrefix("www.") { return true }
        if lowered.contains("@"), lowered.contains("."), !lowered.contains(" ") { return true }
        if text.hasPrefix("/") || text.hasPrefix("~/") { return true }
        let codeSymbols = Set("{}[]()<>=;_/\\|$#*`")
        let symbolCount = text.filter { codeSymbols.contains($0) }.count
        return Double(symbolCount) / Double(max(text.count, 1)) > 0.12
    }

    /// Collapses whitespace and trims the string.
    public static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
