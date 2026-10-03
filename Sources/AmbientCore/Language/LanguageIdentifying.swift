import Foundation

public struct LanguageGuess: Sendable, Equatable {
    /// BCP-47 language code such as "fr", "en", "zh-Hans".
    public let code: String
    public let confidence: Double

    public init(code: String, confidence: Double) {
        self.code = code
        self.confidence = confidence
    }
}

/// Abstraction over a language identifier (NaturalLanguage's
/// `NLLanguageRecognizer` in the app) so the filtering logic stays testable.
public protocol LanguageIdentifying: Sendable {
    func identify(_ text: String) -> LanguageGuess?
}

public enum LanguageCode {
    /// "zh-Hans" -> "zh", "en_US" -> "en".
    public static func base(_ code: String) -> String {
        let separators = CharacterSet(charactersIn: "-_")
        return code.components(separatedBy: separators).first?.lowercased() ?? code.lowercased()
    }
}
