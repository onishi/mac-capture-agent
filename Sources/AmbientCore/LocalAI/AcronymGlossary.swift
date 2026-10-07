import Foundation

/// An abbreviation defined in on-screen text ("Retrieval-Augmented Generation (RAG)").
public struct AcronymDefinition: Sendable, Equatable {
    public let acronym: String
    public let expansion: String

    public init(acronym: String, expansion: String) {
        self.acronym = acronym
        self.expansion = expansion
    }
}

/// Learns abbreviations from definitions written on screen and recalls them
/// when the abbreviation shows up again elsewhere — no language model needed
/// (SPEC LA-6). Kept in memory only, bounded, never written to disk.
public struct AcronymGlossary: Sendable {
    public let capacity: Int
    private var entries: [String: AcronymDefinition] = [:]
    private var order: [String] = []

    public init(capacity: Int = 300) {
        self.capacity = max(1, capacity)
    }

    public var count: Int { entries.count }

    /// Records every definition found in `text`; returns the new ones.
    @discardableResult
    public mutating func learn(from text: String) -> [AcronymDefinition] {
        var added: [AcronymDefinition] = []
        for definition in Self.definitions(in: text) {
            let key = definition.acronym.uppercased()
            if entries[key] == nil { added.append(definition) }
            entries[key] = definition
            order.removeAll { $0 == key }
            order.append(key)
        }
        while order.count > capacity {
            entries.removeValue(forKey: order.removeFirst())
        }
        return added
    }

    public func lookup(_ acronym: String) -> AcronymDefinition? {
        entries[acronym.uppercased()]
    }

    public mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    // MARK: Extraction

    private static let acronymPattern = #"[A-Z][A-Za-z0-9&]{1,9}s?"#
    /// "Long Form (ABC)" — the long form is the words right before the parenthesis.
    private static let longThenShort = CompiledPattern(#"((?:[A-Za-z][\w'’\-]*[ \-]){1,10}[A-Za-z][\w'’\-]*)\s*[(（](\#(acronymPattern))[)）]"#)
    /// "ABC (Long Form)".
    private static let shortThenLong = CompiledPattern(#"\b(\#(acronymPattern))\s*[(（]((?:[A-Za-z][\w'’\-]*[ \-]){1,10}[A-Za-z][\w'’\-]*)[)）]"#)

    /// Definitions whose long form matches the abbreviation's letters.
    public static func definitions(in text: String) -> [AcronymDefinition] {
        var result: [AcronymDefinition] = []
        for groups in longThenShort.captures(in: text) {
            guard groups.count == 3, let long = groups[1], let short = groups[2] else { continue }
            if let definition = match(acronym: short, candidate: long) { result.append(definition) }
        }
        for groups in shortThenLong.captures(in: text) {
            guard groups.count == 3, let short = groups[1], let long = groups[2] else { continue }
            if let definition = match(acronym: short, candidate: long) { result.append(definition) }
        }
        return result
    }

    /// Finds the shortest tail of `candidate` whose words spell the acronym
    /// (a word may give several leading letters, as in "HTTP Secure").
    static func match(acronym rawAcronym: String, candidate: String) -> AcronymDefinition? {
        var acronym = rawAcronym
        if acronym.count > 2, acronym.hasSuffix("s") { acronym.removeLast() }   // plural "APIs"
        let letters = Array(acronym.lowercased().filter(\.isLetter))
        guard letters.count >= 2, acronym.contains(where: \.isUppercase),
              acronym.filter(\.isUppercase).count >= 2 else { return nil }
        let words = candidate
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
            .map(String.init)
        guard !words.isEmpty else { return nil }
        let stopWords: Set<String> = ["of", "the", "and", "for", "to", "in", "on", "a", "an", "with", "by"]
        // Try tails from the shortest; the long form ends right before the parenthesis.
        for start in stride(from: words.count - 1, through: 0, by: -1) {
            let tail = Array(words[start...])
            guard tail.count <= letters.count + 3 else { break }
            guard let first = tail.first, let initial = first.first, let firstLetter = letters.first,
                  initial.lowercased() == String(firstLetter),
                  !stopWords.contains(first.lowercased()) else { continue }
            if spells(letters, with: tail, stopWords: stopWords) {
                let expansion = tail.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
                guard expansion.count <= 80, EntityName.canonical(expansion) != EntityName.canonical(acronym) else { return nil }
                return AcronymDefinition(acronym: acronym, expansion: expansion)
            }
        }
        return nil
    }

    /// Every acronym letter is matched in order. Each significant word gives
    /// a non-empty prefix ("HTTP Secure" → H·T·T·P + S); stop words and the
    /// later parts of hyphenated words may give none ("Conflict-free" → C).
    private static func spells(_ letters: [Character], with words: [String], stopWords: Set<String>) -> Bool {
        var parts: [(letters: [Character], optional: Bool)] = []
        for word in words {
            let pieces = word.lowercased().split(separator: "-")
                .map { Array($0.filter { $0.isLetter || $0.isNumber }) }
                .filter { !$0.isEmpty }
            for (index, piece) in pieces.enumerated() {
                parts.append((piece, index > 0 || stopWords.contains(String(piece))))
            }
        }
        func walk(_ part: Int, _ letter: Int) -> Bool {
            if part == parts.count { return letter == letters.count }
            let current = parts[part]
            if current.optional, walk(part + 1, letter) { return true }
            var length = 0
            while length < current.letters.count, letter + length < letters.count,
                  current.letters[length] == letters[letter + length] {
                length += 1
                if walk(part + 1, letter + length) { return true }
            }
            return false
        }
        return walk(0, 0)
    }
}
