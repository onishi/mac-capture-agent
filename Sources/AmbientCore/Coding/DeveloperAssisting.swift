import Foundation

public struct ErrorExplanation: Sendable, Equatable {
    /// The most likely cause, one sentence.
    public let cause: String
    /// A concrete next step, if any.
    public let fix: String?

    public init(cause: String, fix: String?) {
        self.cause = cause
        self.fix = fix
    }
}

public struct CodeSummary: Sendable, Equatable {
    public let isCode: Bool
    /// What the code does, one to three short sentences.
    public let summary: String

    public init(isCode: Bool, summary: String) {
        self.isCode = isCode
        self.summary = summary
    }
}

/// Coding Mode assistance on-device (Foundation Models in the app).
public protocol DeveloperAssisting: Sendable {
    var isAvailable: Bool { get }
    func explainError(_ error: String, context: String, targetLanguage: String) async throws -> ErrorExplanation
    func summarizeCode(_ code: String, targetLanguage: String) async throws -> CodeSummary
}

public enum DeveloperOutputSanitizer {
    public static let maximumLength = 160

    public static func sanitize(_ explanation: ErrorExplanation, errorLine: String) -> ErrorExplanation? {
        let cause = clean(explanation.cause)
        guard !cause.isEmpty, EntityName.canonical(cause) != EntityName.canonical(errorLine) else { return nil }
        let fix = explanation.fix.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        return ErrorExplanation(cause: cause, fix: fix)
    }

    public static func sanitize(_ summary: CodeSummary) -> CodeSummary? {
        guard summary.isCode else { return nil }
        let text = clean(summary.summary)
        return text.isEmpty ? nil : CodeSummary(isCode: true, summary: text)
    }

    private static func clean(_ text: String) -> String {
        let collapsed = TextHeuristics.normalized(text.replacingOccurrences(of: "\n", with: " "))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」*` "))
        return collapsed.count > maximumLength ? String(collapsed.prefix(maximumLength - 1)) + "…" : collapsed
    }

    /// Cheap check that dwelled-on text is code (before asking the model).
    public static func looksLikeCode(_ text: String) -> Bool {
        let markers = ["func ", "function ", "def ", "class ", "struct ", "return ", "let ", "var ", "const ",
                       "import ", "=>", "->", "{", "}", "();", "if (", "for (", "#include", "public ", "private "]
        let hits = markers.filter { text.contains($0) }.count
        return hits >= 2 || TextHeuristics.looksLikeCodeOrIdentifier(text)
    }
}
