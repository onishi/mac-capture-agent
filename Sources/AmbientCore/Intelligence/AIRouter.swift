import Foundation

/// Decides whether anything on screen is worth showing to the user right now.
///
/// Ignore-first: the default answer is `.ignore`, and a candidate is only
/// returned when its interest score reaches the "show" level.
public final class AIRouter: Sendable {
    private let detector: ForeignTextDetector
    private let scorer: InterestScorer
    private let adjuster: any InterestAdjusting

    public init(
        detector: ForeignTextDetector,
        scorer: InterestScorer = InterestScorer(),
        adjuster: any InterestAdjusting = NoPersonalization()
    ) {
        self.detector = detector
        self.scorer = scorer
        self.adjuster = adjuster
    }

    /// The single best action for this context, or `.ignore`.
    public func route(_ context: AnalysisContext) -> RoutedAction {
        candidates(for: context).first { $0.interestScore.level == .show } ?? .ignore
    }

    /// All scored candidates, most important first (useful for debugging and tests).
    public func candidates(for context: AnalysisContext) -> [RoutedAction] {
        var result: [RoutedAction] = []

        for region in context.textRegions {
            guard let foreign = detector.evaluate(region.text).foreignText else { continue }
            let raw = scorer.scoreTranslation(foreign, region: region, context: context)
            let score = adjuster.adjust(raw, action: .translate, context: context)
            result.append(RoutedAction(
                action: .translate,
                confidence: foreign.language.confidence,
                importance: score.value,
                region: region.boundingBox,
                payload: foreign.text,
                sourceLanguage: foreign.language.code
            ))
        }

        for category in Set(context.visualCategories) {
            guard let action = Self.visualAction(for: category) else { continue }
            let score = adjuster.adjust(scorer.scoreVisual(category, context: context), action: action, context: context)
            result.append(RoutedAction(action: action, confidence: 0.5, importance: score.value, region: nil, payload: nil))
        }

        return result.sorted { $0.importance > $1.importance }
    }

    private static func visualAction(for category: VisualCategory) -> SuggestedAction? {
        switch category {
        case .animal: return .identifyAnimal
        case .plant: return .identifyPlant
        case .landmark: return .identifyLandmark
        case .person: return .identifyPerson
        case .food, .text, .unknown: return nil
        }
    }
}
