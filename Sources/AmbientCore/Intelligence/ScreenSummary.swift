import Foundation

/// Summarizes what is on screen on-device (Foundation Models in the app), on request.
public protocol ScreenSummarizing: Sendable {
    var isAvailable: Bool { get }
    func summarize(text: String, title: String?, targetLanguage: String) async throws -> String
}

/// "Summarize this screen" (SPEC LA-10): the visible text of the page,
/// in reading order, condensed into up to three short lines.
public enum ScreenSummary {
    /// Less text than this is not worth summarizing.
    public static let minimumInputLength = 200
    public static let maximumInputLength = 4_000
    public static let maximumLines = 3
    public static let maximumLineLength = 90

    public static func instructions(targetLanguage: String) -> String {
        """
        Summarize the text the user has on screen (an article, a document, a thread) in at most \(maximumLines) short \
        lines, one point per line, most important first. Use only the given text; skip menus, buttons, ads and \
        navigation. Do not add opinions or facts that are not in the text. Answer in the language with code \
        "\(targetLanguage)".
        """
    }

    public static func prompt(text: String, title: String?) -> String {
        let clipped = text.count > maximumInputLength ? String(text.prefix(maximumInputLength)) : text
        return (title.map { "Title: \($0)\n" } ?? "") + "Text:\n" + clipped
    }

    /// Up to three clean lines (bullets and numbering removed), or nil.
    public static func sanitize(_ answer: String, input: String) -> [String]? {
        let lines = answer
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var text = TextHeuristics.normalized(String(line))
                while let first = text.first, "-•*・▸0123456789.)） ".contains(first) { text.removeFirst() }
                text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」*` "))
                return text.count > maximumLineLength ? String(text.prefix(maximumLineLength - 1)) + "…" : text
            }
            .filter { $0.count >= 4 && !input.contains($0) }
        let result = Array(lines.prefix(maximumLines))
        return result.isEmpty ? nil : result
    }
}
