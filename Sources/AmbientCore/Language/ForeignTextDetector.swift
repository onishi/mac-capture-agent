import Foundation

public struct ForeignTextDetectorConfiguration: Sendable, Equatable {
    /// Language the user wants to read (translation target), e.g. "ja".
    public var userLanguage: String
    /// Additional languages the user reads comfortably; they are never translated.
    public var familiarLanguages: Set<String>
    /// Minimum number of letters for space-separated scripts.
    public var minimumLetters: Int = 8
    /// Minimum number of words for space-separated scripts.
    public var minimumWords: Int = 2
    /// Minimum number of CJK characters for scripts without spaces.
    public var minimumCJKCharacters: Int = 4
    /// Minimum identifier confidence.
    public var minimumConfidence: Double = 0.6
    /// Stricter confidence for short text, where identification is unreliable.
    public var shortTextConfidence: Double = 0.8
    public var shortTextLength: Int = 24
    /// Text longer than this is cut before identification.
    public var maximumLength: Int = 1_000

    public init(userLanguage: String, familiarLanguages: Set<String> = []) {
        self.userLanguage = userLanguage
        self.familiarLanguages = familiarLanguages
    }

    /// Base codes of all languages the user can read.
    public var readableBaseLanguages: Set<String> {
        Set(([userLanguage] + Array(familiarLanguages)).map(LanguageCode.base))
    }
}

public struct ForeignText: Sendable, Equatable {
    public let text: String
    public let language: LanguageGuess
    public let heuristics: TextHeuristics
}

public enum TextEvaluation: Sendable, Equatable {
    case foreign(ForeignText)
    case ignored(IgnoreReason)

    public enum IgnoreReason: String, Sendable, Equatable {
        case tooShort
        case commonPhrase
        case notProse
        case unknownLanguage
        case lowConfidence
        case familiarLanguage
    }

    public var foreignText: ForeignText? {
        if case .foreign(let text) = self { return text }
        return nil
    }
}

/// Decides whether a piece of text is a foreign-language sentence worth translating.
/// Rejects aggressively: anything short, UI-ish, code-like or ambiguous is ignored.
public struct ForeignTextDetector: Sendable {
    public let configuration: ForeignTextDetectorConfiguration
    private let identifier: any LanguageIdentifying

    public init(identifier: any LanguageIdentifying, configuration: ForeignTextDetectorConfiguration) {
        self.identifier = identifier
        self.configuration = configuration
    }

    public func evaluate(_ rawText: String) -> TextEvaluation {
        let text = String(TextHeuristics.normalized(rawText).prefix(configuration.maximumLength))
        let stats = TextHeuristics(text)

        let isCJKText = stats.cjkCount * 2 >= stats.letterCount && stats.cjkCount > 0
        if isCJKText {
            guard stats.cjkCount >= configuration.minimumCJKCharacters else { return .ignored(.tooShort) }
        } else {
            guard stats.letterCount >= configuration.minimumLetters,
                  stats.wordCount >= configuration.minimumWords else { return .ignored(.tooShort) }
        }
        if CommonVocabulary.isCommonPhrase(text) { return .ignored(.commonPhrase) }
        if stats.letterRatio < 0.6 || TextHeuristics.looksLikeCodeOrIdentifier(text) { return .ignored(.notProse) }

        guard let guess = identifier.identify(text), guess.code != "und" else { return .ignored(.unknownLanguage) }
        let requiredConfidence = text.count < configuration.shortTextLength
            ? configuration.shortTextConfidence
            : configuration.minimumConfidence
        guard guess.confidence >= requiredConfidence else { return .ignored(.lowConfidence) }
        if configuration.readableBaseLanguages.contains(LanguageCode.base(guess.code)) {
            return .ignored(.familiarLanguage)
        }
        return .foreign(ForeignText(text: text, language: guess, heuristics: stats))
    }
}
