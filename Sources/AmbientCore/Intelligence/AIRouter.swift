import Foundation

/// Decides whether anything on screen is worth showing to the user right now.
///
/// Ignore-first: the default answer is `.ignore`, and a candidate is only
/// returned when its interest score reaches the "show" level.
public final class AIRouter: Sendable {
    private let detector: ForeignTextDetector
    private let scorer: InterestScorer
    private let adjuster: any InterestAdjusting
    private let termExtractor = TermExtractor()
    private let errorDetector = ErrorDetector()

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
        decide(context).selected
    }

    /// The selected action together with every scored candidate (for diagnostics).
    public func decide(_ context: AnalysisContext) -> RouterDecision {
        let candidates = candidates(for: context)
        let selected = candidates.first { $0.interestScore.level == .show } ?? .ignore
        return RouterDecision(selected: selected, candidates: candidates)
    }

    /// All scored candidates, most important first (useful for debugging and tests).
    public func candidates(for context: AnalysisContext) -> [RoutedAction] {
        var result: [RoutedAction] = []

        for region in context.textRegions {
            guard let foreign = detector.evaluate(region.text).foreignText else { continue }
            let raw = scorer.scoreTranslation(foreign, region: region, context: context)
            let features = PersonalizationFeatures(action: .translate, language: foreign.language.code, bundleIdentifier: context.bundleIdentifier)
            let score = adjuster.adjust(raw, features: features)
            result.append(RoutedAction(
                action: .translate,
                confidence: foreign.language.confidence,
                importance: score.value,
                region: region.boundingBox,
                payload: foreign.text,
                sourceLanguage: foreign.language.code
            ))
        }

        if let error = errorDetector.detect(in: context.textRegions) {
            let features = PersonalizationFeatures(action: .explainError, language: nil, bundleIdentifier: context.bundleIdentifier)
            let score = adjuster.adjust(scorer.scoreError(error, context: context), features: features)
            result.append(RoutedAction(
                action: .explainError,
                confidence: 0.8,
                importance: score.value,
                region: error.region,
                payload: error.line,
                sourceLanguage: nil,
                context: error.context
            ))
        }

        // Terms are explained outside Coding Mode only; in an IDE nearly every
        // identifier looks like jargon.
        let terms = AppContextClassifier.classify(context) == .coding ? [] : termExtractor.candidates(in: context.textRegions)
        for term in terms {
            let features = PersonalizationFeatures(action: .explainTerm, language: nil, bundleIdentifier: context.bundleIdentifier)
            let score = adjuster.adjust(scorer.scoreTerm(term, context: context), features: features)
            result.append(RoutedAction(
                action: .explainTerm,
                confidence: 0.5,
                importance: score.value,
                region: term.region,
                payload: term.term,
                context: term.context
            ))
        }

        for category in Set(context.visualCategories) {
            guard let action = Self.visualAction(for: category) else { continue }
            let features = PersonalizationFeatures(action: action, language: nil, bundleIdentifier: context.bundleIdentifier)
            let score = adjuster.adjust(scorer.scoreVisual(category, context: context), features: features)
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

public struct RouterDecision: Sendable, Equatable {
    public let selected: RoutedAction
    /// Most important first.
    public let candidates: [RoutedAction]
}
