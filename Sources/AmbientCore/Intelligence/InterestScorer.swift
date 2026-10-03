import Foundation

/// Rule-based estimate of how valuable a candidate would be to the user right now.
public struct InterestScorer: Sendable {
    /// Text whose top edge is above this (normalized) is assumed to be in the menu bar.
    public var menuBarHeight: CGFloat = 0.035

    public init() {}

    public func scoreTranslation(
        _ foreign: ForeignText,
        region: RecognizedTextRegion,
        context: AnalysisContext
    ) -> InterestScore {
        var score = 0.45
        score += 0.25 * foreign.language.confidence

        let letters = foreign.heuristics.letterCount
        switch letters {
        case 15...280: score += 0.15
        case 8..<15: score += 0.05
        case 600...: score -= 0.15
        default: break
        }

        if region.confidence < 0.5 {
            score -= 0.2
        } else {
            score += 0.05 * Double(region.confidence)
        }

        if let last = foreign.text.trimmingCharacters(in: .whitespaces).last, ".!?。！？".contains(last) {
            score += 0.05
        }

        if region.boundingBox.minY < menuBarHeight {
            score -= 0.3
        }

        if AppContextClassifier.classify(bundleIdentifier: context.bundleIdentifier) == .coding {
            // Code, identifiers and logs are mostly English; wait for Coding Mode.
            score -= 0.15
        }

        return InterestScore(score)
    }

    /// Visual identification is not implemented in v0.1, so these stay below the
    /// show threshold. Person identification is deliberately kept very low.
    public func scoreVisual(_ category: VisualCategory, context: AnalysisContext) -> InterestScore {
        switch category {
        case .animal, .plant, .landmark: return InterestScore(0.35)
        case .person: return InterestScore(0.05)
        case .food, .text, .unknown: return InterestScore(0)
        }
    }
}
