import Foundation

/// The in-memory, Codable index behind the memory store: retention, pruning
/// and hybrid (keyword + semantic + recency) search. Pure value type.
public struct VisualMemoryIndex: Sendable, Equatable, Codable {
    public var retention: TimeInterval
    public var maximumEntries: Int
    /// Newest first.
    public private(set) var entries: [VisualMemoryEntry] = []

    public init(retention: TimeInterval = 7 * 24 * 60 * 60, maximumEntries: Int = 1_000) {
        self.retention = retention
        self.maximumEntries = max(1, maximumEntries)
    }

    public mutating func add(_ entry: VisualMemoryEntry, now: Date) {
        entries.removeAll { $0.id == entry.id }
        // The same text seen again only refreshes its timestamp.
        entries.removeAll { $0.original == entry.original && $0.translation == entry.translation }
        entries.insert(entry, at: 0)
        entries.sort { $0.timestamp > $1.timestamp }
        prune(now: now)
    }

    public mutating func updateBriefing(_ briefing: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].briefing = briefing
    }

    public mutating func prune(now: Date) {
        entries.removeAll { now.timeIntervalSince($0.timestamp) > retention }
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// - Parameters:
    ///   - queryEmbedding: embedding of `query.text` in the user's language, if available.
    public func search(_ query: MemoryQuery, queryEmbedding: [Float]?, now: Date, limit: Int) -> [MemorySearchResult] {
        let filtered = entries.filter { entry in
            if let range = query.dateRange, !range.contains(entry.timestamp) { return false }
            if let language = query.language, entry.sourceLanguage.map(LanguageCode.base) != language { return false }
            return true
        }
        let hasText = !query.text.trimmingCharacters(in: .whitespaces).isEmpty

        let results: [MemorySearchResult] = filtered.compactMap { entry in
            let recency = 0.1 * exp(-now.timeIntervalSince(entry.timestamp) / (3 * 24 * 60 * 60))
            guard hasText else { return MemorySearchResult(entry: entry, score: 0.5 + recency) }
            let keyword = Self.keywordScore(query.text, in: entry.searchableText)
            let semantic = Self.semanticScore(queryEmbedding, entry.embedding)
            let relevance = max(keyword, semantic * 0.9)
            // Without filters, require real relevance. With filters, keep every
            // match of the filter but rank relevant ones first.
            guard relevance >= 0.25 || query.hasFilters else { return nil }
            return MemorySearchResult(entry: entry, score: relevance + recency)
        }
        return Array(results.sorted {
            $0.score == $1.score ? $0.entry.timestamp > $1.entry.timestamp : $0.score > $1.score
        }.prefix(max(0, limit)))
    }

    /// Fraction of query terms found. CJK terms (no spaces) are matched by bigrams.
    static func keywordScore(_ query: String, in text: String) -> Double {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return 0 }
        let scores = terms.map { term -> Double in
            if text.contains(term) { return 1 }
            let characters = Array(term)
            let isCJK = term.unicodeScalars.contains(where: TextHeuristics.isCJK)
            guard isCJK, characters.count >= 3 else { return 0 }
            let bigrams = (0..<(characters.count - 1)).map { String(characters[$0...$0 + 1]) }
            let hits = bigrams.filter { text.contains($0) }.count
            return Double(hits) / Double(bigrams.count)
        }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Cosine similarity mapped from [0.3, 1] to [0, 1].
    static func semanticScore(_ a: [Float]?, _ b: [Float]?) -> Double {
        guard let a, let b, a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        let cosine = Double(dot / (na.squareRoot() * nb.squareRoot()))
        return min(1, max(0, (cosine - 0.3) / 0.7))
    }
}
