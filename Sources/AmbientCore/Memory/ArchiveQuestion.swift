import Foundation

/// One archived record handed to the model as evidence.
public struct ArchiveEvidence: Sendable, Equatable {
    public let date: Date
    public let application: String?
    public let text: String

    public init(date: Date, application: String?, text: String) {
        self.date = date
        self.application = application
        self.text = text
    }

    public init(_ entry: VisualMemoryEntry) {
        let body = entry.original == entry.translation ? entry.original : "\(entry.original) → \(entry.translation)"
        self.init(date: entry.timestamp, application: entry.application, text: body)
    }
}

/// Answers a question about the archive on-device (Foundation Models in the app).
public protocol ArchiveAnswering: Sendable {
    var isAvailable: Bool { get }
    func answer(question: String, evidence: [ArchiveEvidence], targetLanguage: String) async throws -> String
}

/// "Ask the archive" (LOCAL_AI.md LA-30): a local RAG that answers only from
/// what the user's own archive contains.
public enum ArchiveQuestion {
    public static let maximumEvidence = 8
    public static let maximumEvidenceLength = 220
    public static let maximumAnswerLength = 400
    /// The model's way to say the records don't contain the answer.
    public static let notFoundMarker = "NOT_FOUND"

    /// A query is a question when it ends with "?" / "？" or starts with "?".
    public static func isQuestion(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question(from: trimmed).count >= 3 else { return false }
        return trimmed.hasPrefix("?") || trimmed.hasPrefix("？") || trimmed.hasSuffix("?") || trimmed.hasSuffix("？")
    }

    /// The question without a leading "?" marker.
    public static func question(from query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, first == "?" || first == "？" { text.removeFirst() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    public static func instructions(targetLanguage: String) -> String {
        """
        You answer the user's question about things they saw on their own screen. You get numbered records from \
        their private archive (date, app, text). Answer ONLY from these records, in one to three short sentences, \
        and cite the records you used like [2]. If the records do not contain the answer, reply exactly \
        \(notFoundMarker). Never use outside knowledge. Answer in the language with code "\(targetLanguage)".
        """
    }

    public static func prompt(question: String, evidence: [ArchiveEvidence], now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lines = evidence.prefix(maximumEvidence).enumerated().map { index, item in
            let text = TextHeuristics.normalized(item.text.replacingOccurrences(of: "\n", with: " "))
            let clipped = text.count > maximumEvidenceLength ? String(text.prefix(maximumEvidenceLength - 1)) + "…" : text
            return "[\(index + 1)] \(formatter.string(from: item.date)) \(item.application ?? "-"): \(clipped)"
        }
        return """
            Today: \(formatter.string(from: now))
            Question: \(question)
            Records:
            \(lines.joined(separator: "\n"))
            """
    }

    /// The cleaned answer, or nil when the model found nothing (or answered emptily).
    public static func sanitize(_ answer: String) -> String? {
        let collapsed = TextHeuristics.normalized(answer.replacingOccurrences(of: "\n", with: " "))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」*` "))
        guard !collapsed.isEmpty, !collapsed.contains(notFoundMarker) else { return nil }
        return collapsed.count > maximumAnswerLength ? String(collapsed.prefix(maximumAnswerLength - 1)) + "…" : collapsed
    }

    /// Record numbers the answer cites ("[2]", "[1][3]"), in order, within the evidence count.
    public static func citations(in answer: String, evidenceCount: Int) -> [Int] {
        var result: [Int] = []
        for groups in CompiledPattern(#"\[(\d{1,2})\]"#).captures(in: answer) {
            guard groups.count > 1, let number = groups[1].flatMap({ Int($0) }),
                  (1...max(1, evidenceCount)).contains(number), !result.contains(number) else { continue }
            result.append(number)
        }
        return result
    }
}
