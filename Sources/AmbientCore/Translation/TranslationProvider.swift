import Foundation

public protocol TranslationProvider: Sendable {
    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String
}

public enum TranslationProviderError: Error, Equatable, Sendable {
    case unavailable
    case unsupportedLanguagePair(source: String?, target: String)
    /// The language pair is supported but its model is not downloaded yet.
    case languageNotInstalled(source: String?, target: String)
    case timedOut
    case emptyResult
}

/// Placeholder provider used when no real translation backend is available.
/// It fails, and failures are never surfaced in the HUD.
public struct UnavailableTranslationProvider: TranslationProvider {
    public init() {}
    public func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        throw TranslationProviderError.unavailable
    }
}

/// Validates a translation result before it is shown.
public enum TranslationResultValidator {
    /// A translation identical to the source (ignoring case/whitespace) or empty is useless.
    public static func isUseful(original: String, translated: String) -> Bool {
        let a = TextHeuristics.normalized(original).lowercased()
        let b = TextHeuristics.normalized(translated).lowercased()
        return !b.isEmpty && a != b
    }
}
