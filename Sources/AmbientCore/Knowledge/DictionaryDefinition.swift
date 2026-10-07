import Foundation

/// Looks a word up in the Mac's built-in dictionaries (Dictionary Services in the app).
public protocol DictionaryLooking: Sendable {
    func definition(of term: String) -> String?
}

/// Turns a raw dictionary entry into one short line for the HUD (LOCAL_AI.md LA-5).
public enum DictionaryDefinition {
    public static let maximumLength = 160

    private static let pronunciation = CompiledPattern(#"\|[^|]{1,60}\|"#)
    private static let senseNumber = CompiledPattern(#"(?:^|\s)[1-9]\s+(?=\S)|[①-⑳]|▸"#)

    /// The first sense, without the headword, pronunciation or sense numbers;
    /// nil when nothing useful is left.
    public static func sanitize(_ raw: String, term: String) -> String? {
        var text = TextHeuristics.normalized(raw.replacingOccurrences(of: "\n", with: " "))
        // Drop the headword the entry starts with ("RAG | ræɡ | noun …", "ラグ【rag】…").
        if text.lowercased().hasPrefix(term.lowercased()) {
            text = String(text.dropFirst(term.count)).trimmingCharacters(in: .whitespaces)
        }
        while let range = pronunciation.firstRange(in: text) {
            text.removeSubrange(range)
        }
        if let open = text.firstIndex(of: "【"), let close = text.firstIndex(of: "】"), open < close,
           text.distance(from: text.startIndex, to: open) < 12 {
            text.removeSubrange(text.startIndex...close)
        }
        // Keep the first sense: cut where the second numbered sense starts.
        let senses = senseNumber.matchesWithRanges(in: text)
        if senses.count >= 2 {
            text = String(text[..<senses[1].range.lowerBound])
        }
        if let first = senseNumber.firstRange(in: text) {
            text.replaceSubrange(first, with: " ")
        }
        text = TextHeuristics.normalized(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:・|").union(.whitespaces))
        guard text.count >= 4, EntityName.canonical(text) != EntityName.canonical(term) else { return nil }
        return text.count > maximumLength ? String(text.prefix(maximumLength - 1)) + "…" : text
    }
}
