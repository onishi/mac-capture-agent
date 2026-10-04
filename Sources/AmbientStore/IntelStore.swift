import Foundation
import GRDB
import OSLog
#if canImport(AmbientCore)
import AmbientCore
#endif

/// A cached explanation of a term (Knowledge Cache).
struct KnowledgeRecord: Sendable, Equatable {
    let name: String
    let summary: String
    let detail: String?
    let source: String
    let expiresAt: Date
}

/// SQLite-backed visual memory, entity sightings and Knowledge Cache.
/// All errors are logged and swallowed: storage problems never reach the UI.
actor IntelStore: VisualMemoryStore {
    private let database: IntelDatabase?
    private var retention: TimeInterval
    private var userLanguage: String
    private let embedding: any TextEmbedding
    private let embeddingModel: String
    /// Rows considered by one search before ranking.
    private let searchWindow = 2_000
    private static let logger = Logger(subsystem: "com.onishi.AmbientScreenIntelligence", category: "store")

    init(url: URL?, retentionDays: Int, userLanguage: String, embedding: any TextEmbedding, embeddingModel: String = "nl-sentence") {
        do {
            database = try IntelDatabase(url: url)
        } catch {
            Self.logger.error("Database unavailable: \(error.localizedDescription, privacy: .public)")
            database = nil
        }
        self.retention = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        self.userLanguage = userLanguage
        self.embedding = embedding
        self.embeddingModel = embeddingModel
    }

    var isAvailable: Bool { database != nil }

    func configure(retentionDays: Int, userLanguage: String) {
        retention = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        self.userLanguage = userLanguage
        prune(now: Date())
    }

    // MARK: VisualMemoryStore

    func remember(_ entry: VisualMemoryEntry) {
        var entry = entry
        if entry.embedding == nil {
            entry.embedding = embedding.vector(for: entry.translation, language: entry.targetLanguage ?? userLanguage)
        }
        let model = embeddingModel
        let stored = entry
        perform("remember") { db in
            // The same text seen again only refreshes its timestamp.
            let duplicates = try String.fetchAll(db, sql: """
                SELECT o.id FROM observation o JOIN intel i ON i.observation_id = o.id
                WHERE o.text = ? AND i.body = ? AND o.id != ?
                """, arguments: [stored.original, stored.translation, stored.id.uuidString])
            try Self.delete(intelIDs: duplicates, in: db)
            try Self.insert(stored, model: model, in: db)
        }
        prune(now: Date())
    }

    func updateBriefing(_ briefing: String, for id: UUID) {
        perform("updateBriefing") { db in
            try db.execute(sql: "UPDATE intel SET briefing = ? WHERE id = ?", arguments: [briefing, id.uuidString])
            try db.execute(sql: "UPDATE intel_fts SET briefing = ? WHERE intel_id = ?", arguments: [briefing, id.uuidString])
        }
    }

    func search(_ query: String, limit: Int) -> [MemorySearchResult] {
        let now = Date()
        prune(now: now)
        let parsed = MemoryQueryParser.parse(query, now: now)
        let queryEmbedding = parsed.text.isEmpty ? nil : embedding.vector(for: parsed.text, language: userLanguage)
        let model = embeddingModel
        let window = searchWindow
        let entries = read("search") { db in try Self.candidates(for: parsed, model: model, window: window, in: db) } ?? []
        return VisualMemoryIndex.rank(entries, query: parsed, queryEmbedding: queryEmbedding, now: now, limit: limit)
    }

    func count() -> Int {
        read("count") { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM intel") ?? 0 } ?? 0
    }

    func removeAll() {
        perform("removeAll") { db in
            try db.execute(sql: "DELETE FROM observation; DELETE FROM embedding; DELETE FROM intel_fts; DELETE FROM work_session;")
        }
        Self.logger.info("Visual memory purged")
    }

    // MARK: Entities & knowledge

    /// Links entities to an observation that was stored with `remember`.
    func recordEntities(_ entities: [ExtractedEntity], observationID: UUID) {
        guard !entities.isEmpty else { return }
        perform("recordEntities") { db in
            for entity in Set(entities) {
                let id = try Self.upsertEntity(entity, in: db)
                try db.execute(sql: """
                    INSERT OR IGNORE INTO observation_entity (observation_id, entity_id, confidence) VALUES (?, ?, 1.0)
                    """, arguments: [observationID.uuidString, id])
            }
        }
    }

    /// The most recent time any of these entities was seen before `date`
    /// (excluding `excluding`), for re-appearance notices.
    func lastSeen(_ entities: [ExtractedEntity], before date: Date, excluding: UUID?) -> Date? {
        guard !entities.isEmpty else { return nil }
        return read("lastSeen") { db -> Date? in
            var latest: Double?
            for entity in Set(entities) {
                let value = try Double.fetchOne(db, sql: """
                    SELECT max(o.timestamp) FROM observation o
                    JOIN observation_entity oe ON oe.observation_id = o.id
                    JOIN entity e ON e.id = oe.entity_id
                    WHERE e.type = ? AND e.canonical_name = ? AND o.timestamp < ? AND o.id != ?
                    """, arguments: [entity.type.rawValue, entity.canonicalName, date.timeIntervalSince1970, excluding?.uuidString ?? ""])
                if let value { latest = max(latest ?? value, value) }
            }
            return latest.map(Date.init(timeIntervalSince1970:))
        } ?? nil
    }

    func knowledge(forTerm canonical: String, now: Date = Date()) -> KnowledgeRecord? {
        knowledge(type: .term, canonical: canonical, now: now)
    }

    /// Cached knowledge about any entity (term, person, …), if not expired.
    func knowledge(type: EntityType, canonical: String, now: Date = Date()) -> KnowledgeRecord? {
        read("knowledge") { db -> KnowledgeRecord? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT e.name, k.summary, k.detail, k.source, k.expires_at FROM knowledge k
                JOIN entity e ON e.id = k.entity_id
                WHERE e.type = ? AND e.canonical_name = ? AND k.expires_at > ?
                """, arguments: [type.rawValue, canonical, now.timeIntervalSince1970]) else { return nil }
            return KnowledgeRecord(
                name: row["name"],
                summary: row["summary"],
                detail: row["detail"],
                source: row["source"],
                expiresAt: Date(timeIntervalSince1970: row["expires_at"])
            )
        } ?? nil
    }

    func saveKnowledge(term: String, summary: String, detail: String?, source: String, ttl: TimeInterval = 30 * 24 * 60 * 60, now: Date = Date()) {
        saveKnowledge(entity: ExtractedEntity(type: .term, name: term), summary: summary, detail: detail, source: source, ttl: ttl, now: now)
    }

    func saveKnowledge(entity: ExtractedEntity, summary: String, detail: String?, source: String, ttl: TimeInterval = 30 * 24 * 60 * 60, now: Date = Date()) {
        perform("saveKnowledge") { db in
            let id = try Self.upsertEntity(entity, in: db)
            try db.execute(sql: """
                INSERT INTO knowledge (entity_id, summary, detail, source, updated_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(entity_id) DO UPDATE SET summary = excluded.summary, detail = excluded.detail,
                  source = excluded.source, updated_at = excluded.updated_at, expires_at = excluded.expires_at
                """, arguments: [id, summary, detail, source, now.timeIntervalSince1970, now.addingTimeInterval(ttl).timeIntervalSince1970])
        }
    }

    /// Terms the user marked as known, or that were already explained `maxShows` times.
    func shouldSkipTerm(_ canonical: String, maxShows: Int = 3) -> Bool {
        read("shouldSkipTerm") { db -> Bool in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT known, shown_count FROM entity WHERE type = 'term' AND canonical_name = ?
                """, arguments: [canonical]) else { return false }
            let known: Bool = row["known"]
            let shown: Int = row["shown_count"]
            return known || shown >= maxShows
        } ?? false
    }

    func noteTermShown(_ term: String) {
        perform("noteTermShown") { db in
            let id = try Self.upsertEntity(ExtractedEntity(type: .term, name: term), in: db)
            try db.execute(sql: "UPDATE entity SET shown_count = shown_count + 1 WHERE id = ?", arguments: [id])
        }
    }

    func markTermKnown(_ term: String) {
        perform("markTermKnown") { db in
            let id = try Self.upsertEntity(ExtractedEntity(type: .term, name: term), in: db)
            try db.execute(sql: "UPDATE entity SET known = 1 WHERE id = ?", arguments: [id])
        }
    }

    // MARK: Legacy import

    /// Imports the v0.4 JSON archive, then deletes the file. Returns the number of records imported.
    @discardableResult
    func importLegacyJSON(at url: URL) -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        do {
            let data = try Data(contentsOf: url)
            let index = try JSONDecoder().decode(VisualMemoryIndex.self, from: data)
            let model = embeddingModel
            try database?.writer.write { db in
                for entry in index.entries.reversed() {
                    try Self.insert(entry, model: model, in: db)
                }
            }
            try FileManager.default.removeItem(at: url)
            Self.logger.info("Imported \(index.entries.count) legacy records")
            return index.entries.count
        } catch {
            Self.logger.error("Legacy import failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: Private

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retention).timeIntervalSince1970
        perform("prune") { db in
            let expired = try String.fetchAll(db, sql: """
                SELECT i.id FROM intel i JOIN observation o ON o.id = i.observation_id WHERE o.timestamp < ?
                """, arguments: [cutoff])
            try Self.delete(intelIDs: expired, in: db)
            // Bookmarked pages are kept until the user deletes them.
            try db.execute(sql: """
                DELETE FROM observation WHERE timestamp < ? AND id NOT IN (SELECT observation_id FROM bookmark)
                """, arguments: [cutoff])
            try db.execute(sql: "DELETE FROM work_session WHERE ended_at < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM knowledge WHERE expires_at < ?", arguments: [now.timeIntervalSince1970])
        }
    }

    private static func candidates(for query: MemoryQuery, model: String, window: Int, in db: Database) throws -> [VisualMemoryEntry] {
        var conditions: [String] = []
        var arguments: [DatabaseValueConvertible?] = []
        if let range = query.dateRange {
            conditions.append("o.timestamp >= ? AND o.timestamp <= ?")
            arguments += [range.start.timeIntervalSince1970, range.end.timeIntervalSince1970]
        }
        if let language = query.language {
            conditions.append("(i.source_lang = ? OR i.source_lang LIKE ?)")
            arguments += [language, language + "-%"]
        }
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        var ids = try String.fetchAll(db, sql: """
            SELECT i.id FROM intel i JOIN observation o ON o.id = i.observation_id
            \(filter) ORDER BY o.timestamp DESC LIMIT \(window)
            """, arguments: StatementArguments(arguments))

        // Older matches beyond the recency window, found by full-text search.
        let text = query.text.trimmingCharacters(in: .whitespaces)
        if text.count >= 3 {
            let match = "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            let ftsIDs = (try? String.fetchAll(db, sql: "SELECT intel_id FROM intel_fts WHERE intel_fts MATCH ? LIMIT 200", arguments: [match])) ?? []
            let known = Set(ids)
            ids += ftsIDs.filter { !known.contains($0) }
        }
        return try ids.compactMap { try entry(id: $0, model: model, in: db) }
    }

    /// Deletes intel (and its observation, full-text and embedding rows).
    private static func delete(intelIDs: [String], in db: Database) throws {
        for id in intelIDs {
            try db.execute(sql: "DELETE FROM intel_fts WHERE intel_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM embedding WHERE owner_type = 'intel' AND owner_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM observation WHERE id = (SELECT observation_id FROM intel WHERE id = ?)", arguments: [id])
        }
    }

    private static func insert(_ entry: VisualMemoryEntry, model: String, in db: Database) throws {
        let id = entry.id.uuidString
        let featuresJSON = try entry.features.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }
        try db.execute(sql: """
            INSERT OR REPLACE INTO observation (id, timestamp, application, bundle_id, window_title, url, category, confidence, text)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1.0, ?)
            """, arguments: [id, entry.timestamp.timeIntervalSince1970, entry.application, entry.bundleIdentifier,
                             entry.windowTitle, entry.url?.absoluteString,
                             Self.category(for: entry.kind), entry.original])
        try db.execute(sql: """
            INSERT OR REPLACE INTO intel (id, observation_id, kind, body, briefing, source_lang, target_lang, importance, features)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1.0, ?)
            """, arguments: [id, id, entry.kind.rawValue, entry.translation, entry.briefing,
                             entry.sourceLanguage, entry.targetLanguage, featuresJSON])
        try db.execute(sql: "DELETE FROM intel_fts WHERE intel_id = ?", arguments: [id])
        try db.execute(sql: """
            INSERT INTO intel_fts (intel_id, original, body, briefing, context) VALUES (?, ?, ?, ?, ?)
            """, arguments: [id, entry.original, entry.translation, entry.briefing,
                             [entry.application, entry.windowTitle].compactMap { $0 }.joined(separator: " ")])
        if let vector = entry.embedding {
            try db.execute(sql: """
                INSERT OR REPLACE INTO embedding (owner_type, owner_id, model, vector) VALUES ('intel', ?, ?, ?)
                """, arguments: [id, model, VectorCoding.data(from: vector)])
        }
    }

    private static func category(for kind: VisualMemoryEntry.Kind) -> String {
        switch kind {
        case .translation: return "foreign_text"
        case .explanation: return "term"
        case .errorAnalysis: return "error"
        case .codeSummary: return "code"
        case .identification: return "identification"
        case .publicFigure: return "person"
        }
    }

    private static func entry(id: String, model: String, in db: Database) throws -> VisualMemoryEntry? {
        guard let row = try Row.fetchOne(db, sql: """
            SELECT o.timestamp, o.application, o.bundle_id, o.window_title, o.url, o.text,
                   i.kind, i.body, i.briefing, i.source_lang, i.target_lang, i.features,
                   (SELECT vector FROM embedding WHERE owner_type = 'intel' AND owner_id = i.id AND model = ?) AS vector
            FROM intel i JOIN observation o ON o.id = i.observation_id WHERE i.id = ?
            """, arguments: [model, id]),
              let uuid = UUID(uuidString: id)
        else { return nil }
        let urlString: String? = row["url"]
        let featuresJSON: String? = row["features"]
        let vectorData: Data? = row["vector"]
        let kindRaw: String = row["kind"]
        return VisualMemoryEntry(
            id: uuid,
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            kind: VisualMemoryEntry.Kind(rawValue: kindRaw) ?? .translation,
            application: row["application"],
            bundleIdentifier: row["bundle_id"],
            windowTitle: row["window_title"],
            url: urlString.flatMap(URL.init(string:)),
            sourceLanguage: row["source_lang"],
            targetLanguage: row["target_lang"],
            original: row["text"] ?? "",
            translation: row["body"],
            briefing: row["briefing"],
            embedding: vectorData.map(VectorCoding.vector(from:)),
            features: featuresJSON.flatMap { try? JSONDecoder().decode(PersonalizationFeatures.self, from: Data($0.utf8)) }
        )
    }

    private static func upsertEntity(_ entity: ExtractedEntity, in db: Database) throws -> String {
        if let id = try String.fetchOne(db, sql: "SELECT id FROM entity WHERE type = ? AND canonical_name = ?",
                                        arguments: [entity.type.rawValue, entity.canonicalName]) {
            return id
        }
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO entity (id, type, name, canonical_name) VALUES (?, ?, ?, ?)",
                       arguments: [id, entity.type.rawValue, entity.name, entity.canonicalName])
        return id
    }

    func perform(_ operation: String, _ body: (Database) throws -> Void) {
        guard let database else { return }
        do {
            try database.writer.write(body)
        } catch {
            Self.logger.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func read<T>(_ operation: String, _ body: (Database) throws -> T) -> T? {
        guard let database else { return nil }
        do {
            return try database.writer.read(body)
        } catch {
            Self.logger.error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
