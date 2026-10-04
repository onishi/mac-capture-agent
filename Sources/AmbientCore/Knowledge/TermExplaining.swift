import Foundation

/// The model's view of a term: whether it is worth explaining, and how.
public struct TermExplanation: Sendable, Equatable {
    public let shouldExplain: Bool
    /// Expanded form for abbreviations ("Retrieval-Augmented Generation").
    public let expansion: String?
    /// One or two short sentences in the user's language.
    public let summary: String

    public init(shouldExplain: Bool, expansion: String?, summary: String) {
        self.shouldExplain = shouldExplain
        self.expansion = expansion
        self.summary = summary
    }
}

/// Explains technical terms on-device (Foundation Models in the app).
public protocol TermExplaining: Sendable {
    var isAvailable: Bool { get }
    func explain(term: String, context: String, targetLanguage: String) async throws -> TermExplanation
}

/// Second-stage router: asks a model whether an uncertain candidate is worth showing.
public protocol RouterJudging: Sendable {
    var isAvailable: Bool { get }
    func shouldShow(_ candidate: RoutedAction, appName: String?, targetLanguage: String) async throws -> Bool
}

public enum TermExplanationSanitizer {
    public static let maximumSummaryLength = 140
    public static let maximumExpansionLength = 80

    /// Returns a cleaned explanation, or nil when the model declined or the
    /// output is unusable (empty, or just repeats the term).
    public static func sanitize(_ explanation: TermExplanation, term: String) -> TermExplanation? {
        guard explanation.shouldExplain else { return nil }
        let summary = clean(explanation.summary, limit: maximumSummaryLength)
        guard !summary.isEmpty, EntityName.canonical(summary) != EntityName.canonical(term) else { return nil }
        var expansion = explanation.expansion.map { clean($0, limit: maximumExpansionLength) }
        if let value = expansion, value.isEmpty || EntityName.canonical(value) == EntityName.canonical(term) {
            expansion = nil
        }
        return TermExplanation(shouldExplain: true, expansion: expansion, summary: summary)
    }

    private static func clean(_ text: String, limit: Int) -> String {
        let collapsed = TextHeuristics.normalized(text.replacingOccurrences(of: "\n", with: " "))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」*` "))
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    /// Marker stored in the Knowledge Cache when the model decided a term is
    /// not worth explaining, so it isn't asked again for 30 days.
    public static let declinedMarker = ""
}
