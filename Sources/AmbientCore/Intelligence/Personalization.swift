import Foundation

/// User reactions that will be used to tune what gets shown (future work).
public enum PersonalizationFeedback: Sendable, Equatable {
    /// HUD dismissed right away → score −
    case dismissedQuickly
    /// User opened the details → score +
    case openedDetails
    /// User searched for the item → score ++
    case searched
}

/// Adjusts interest scores based on what the user has found useful before.
public protocol InterestAdjusting: Sendable {
    func adjust(_ score: InterestScore, action: SuggestedAction, context: AnalysisContext) -> InterestScore
}

/// v0.1: no personalization yet.
public struct NoPersonalization: InterestAdjusting {
    public init() {}
    public func adjust(_ score: InterestScore, action: SuggestedAction, context: AnalysisContext) -> InterestScore {
        score
    }
}
