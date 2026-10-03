import Foundation

/// What the router suggests doing about the current screen content.
public enum SuggestedAction: String, Sendable, Equatable {
    case translate
    case explainTerm
    case identifyAnimal
    case identifyPlant
    case identifyLandmark
    case identifyPerson
    case ignore
}

public struct RoutedAction: Sendable, Equatable {
    public let action: SuggestedAction
    /// How sure the router is that the detection is correct (0...1).
    public let confidence: Double
    /// How valuable it would be to show this to the user right now (0...1).
    public let importance: Double
    /// Normalized, top-left-origin rect of the target on screen.
    public let region: CGRect?
    /// Action specific payload, e.g. the text to translate.
    public let payload: String?
    /// BCP-47 code of the payload language, when known.
    public let sourceLanguage: String?

    public init(
        action: SuggestedAction,
        confidence: Double,
        importance: Double,
        region: CGRect?,
        payload: String?,
        sourceLanguage: String? = nil
    ) {
        self.action = action
        self.confidence = confidence
        self.importance = importance
        self.region = region
        self.payload = payload
        self.sourceLanguage = sourceLanguage
    }

    public static let ignore = RoutedAction(action: .ignore, confidence: 1, importance: 0, region: nil, payload: nil)

    public var interestScore: InterestScore { InterestScore(importance) }
}
