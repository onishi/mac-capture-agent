import Foundation

/// How an on-device LLM answer ended.
public enum AIAnswerOutcome: String, Codable, Sendable, CaseIterable {
    /// Shown in the HUD.
    case shown
    /// The model itself declined (e.g. "not worth explaining", "not a public figure").
    case declined
    /// The answer was dropped by the app's checks (sanitizer, confidence, name mismatch).
    case filtered
    /// The call failed or timed out.
    case failed
}

/// One answer of the on-device LLM, kept so the user can review what the AI
/// said — including answers that were not shown (SPEC AL-1).
/// Only derived text: the subject is what the question was about (a term, a
/// name, the first line of an error or of circled text), never a screenshot.
public struct AIAnswerRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let feature: IntelFeature
    public let subject: String
    public let answer: String
    public let outcome: AIAnswerOutcome
    public let durationMilliseconds: Int?
    public let application: String?

    public static let maximumSubjectLength = 120
    public static let maximumAnswerLength = 600

    public init(id: UUID = UUID(), date: Date = Date(), feature: IntelFeature, subject: String, answer: String,
                outcome: AIAnswerOutcome, durationMilliseconds: Int? = nil, application: String? = nil) {
        self.id = id
        self.date = date
        self.feature = feature
        self.subject = Self.clip(subject, to: Self.maximumSubjectLength)
        self.answer = Self.clip(answer, to: Self.maximumAnswerLength)
        self.outcome = outcome
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.application = application
    }

    /// One line, collapsed whitespace, cut with an ellipsis.
    static func clip(_ text: String, to limit: Int) -> String {
        let collapsed = TextHeuristics.normalized(text.replacingOccurrences(of: "\n", with: " "))
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    /// Text filter for the archive's AI LOG tab (subject, answer or feature name).
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [subject, answer, feature.title, feature.rawValue].contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
