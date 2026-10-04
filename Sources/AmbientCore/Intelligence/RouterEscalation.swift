import Foundation

/// Second routing stage: candidates the rules are unsure about (optional
/// band, 0.5..<0.7) can be judged by an on-device LLM. Pure policy.
public enum RouterEscalation {
    /// What to ask the model about, most important first.
    public static func candidates(in decision: RouterDecision, limit: Int = 1) -> [RoutedAction] {
        guard decision.selected.action == .ignore else { return [] }
        return Array(decision.candidates.filter { $0.interestScore.level == .optional }.prefix(max(0, limit)))
    }

    /// Applies the model's verdict: accepted candidates are lifted to the show threshold.
    public static func apply(show: Bool, to candidate: RoutedAction) -> RoutedAction {
        guard show else { return .ignore }
        return RoutedAction(
            action: candidate.action,
            confidence: candidate.confidence,
            importance: max(candidate.importance, InterestScore.showThreshold),
            region: candidate.region,
            payload: candidate.payload,
            sourceLanguage: candidate.sourceLanguage,
            context: candidate.context
        )
    }
}

/// Allows an operation at most once per `minimumInterval` (e.g. LLM calls).
public struct RateLimiter: Sendable {
    public let minimumInterval: TimeInterval
    private var last: TimeInterval?

    public init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }

    public mutating func allow(now: TimeInterval) -> Bool {
        if let last, now - last < minimumInterval { return false }
        last = now
        return true
    }
}
