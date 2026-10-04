import Foundation
import GRDB
#if canImport(AmbientCore)
import AmbientCore
#endif

struct BookmarkRecord: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String?
    let url: URL?
    let application: String?
    let timestamp: Date
    let score: Double
    let reasons: [String]
}

struct WorkSessionRecord: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String?
    let start: Date
    let end: Date
    let applications: [String]
    let activeSeconds: TimeInterval
    var bookmarks: [BookmarkRecord] = []
    /// Most-visited page titles (for "pick up where you left off").
    var topPages: [String] = []
}

extension IntelStore {
    // MARK: Page visits

    func recordPageVisit(_ visit: PageVisit) {
        perform("recordPageVisit") { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO observation
                  (id, timestamp, application, bundle_id, window_title, url, category, confidence, text, duration, page_key)
                VALUES (?, ?, ?, ?, ?, ?, 'page', 1.0, NULL, ?, ?)
                """, arguments: [visit.id.uuidString, visit.start.timeIntervalSince1970, visit.application, visit.bundleIdentifier,
                                 visit.title, visit.url?.absoluteString, visit.duration, visit.key.value])
        }
    }

    /// Earlier visits to the same page since `date`.
    func visitCount(_ key: PageKey, since date: Date, excluding id: UUID? = nil) -> Int {
        read("visitCount") { db in
            try Int.fetchOne(db, sql: """
                SELECT count(*) FROM observation WHERE category = 'page' AND page_key = ? AND timestamp >= ? AND id != ?
                """, arguments: [key.value, date.timeIntervalSince1970, id?.uuidString ?? ""]) ?? 0
        } ?? 0
    }

    func pageVisits(since date: Date) -> [PageVisit] {
        read("pageVisits") { db in
            try Row.fetchAll(db, sql: """
                SELECT id, timestamp, duration, application, bundle_id, window_title, url, page_key FROM observation
                WHERE category = 'page' AND timestamp >= ? ORDER BY timestamp
                """, arguments: [date.timeIntervalSince1970]).compactMap(Self.visit(from:))
        } ?? []
    }

    func saveBookmark(observationID: UUID, score: BookmarkScore) {
        perform("saveBookmark") { db in
            try db.execute(sql: """
                INSERT INTO bookmark (observation_id, score, reasons) VALUES (?, ?, ?)
                ON CONFLICT(observation_id) DO UPDATE SET score = excluded.score, reasons = excluded.reasons
                """, arguments: [observationID.uuidString, score.value, score.reasons.map(\.rawValue).joined(separator: ",")])
        }
    }

    func bookmarks(since date: Date, limit: Int = 50) -> [BookmarkRecord] {
        read("bookmarks") { db in
            try Row.fetchAll(db, sql: """
                SELECT o.id, o.window_title, o.url, o.application, o.timestamp, b.score, b.reasons
                FROM bookmark b JOIN observation o ON o.id = b.observation_id
                WHERE o.timestamp >= ? ORDER BY o.timestamp DESC LIMIT ?
                """, arguments: [date.timeIntervalSince1970, limit]).compactMap(Self.bookmark(from:))
        } ?? []
    }

    // MARK: Work sessions

    func sessionName(_ id: UUID) -> String? {
        read("sessionName") { db in
            try String.fetchOne(db, sql: "SELECT title FROM work_session WHERE id = ?", arguments: [id.uuidString])
        } ?? nil
    }

    /// Stores sessions (id = first visit) and links their visits.
    func saveSessions(_ sessions: [(draft: WorkSessionDraft, name: String)]) {
        perform("saveSessions") { db in
            for (draft, name) in sessions {
                let id = draft.id.uuidString
                try db.execute(sql: """
                    INSERT INTO work_session (id, title, started_at, ended_at, apps, active_seconds) VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET title = excluded.title, started_at = excluded.started_at,
                      ended_at = excluded.ended_at, apps = excluded.apps, active_seconds = excluded.active_seconds
                    """, arguments: [id, name, draft.start.timeIntervalSince1970, draft.end.timeIntervalSince1970,
                                     draft.applications.joined(separator: "\n"), draft.activeDuration])
                for visit in draft.visits {
                    try db.execute(sql: "UPDATE observation SET session_id = ? WHERE id = ?", arguments: [id, visit.id.uuidString])
                }
            }
        }
    }

    /// Sessions overlapping `[since, now]`, newest first, with their bookmarks and top pages.
    func sessions(since date: Date, limit: Int = 50) -> [WorkSessionRecord] {
        read("sessions") { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, title, started_at, ended_at, apps, active_seconds FROM work_session
                WHERE ended_at >= ? ORDER BY started_at DESC LIMIT ?
                """, arguments: [date.timeIntervalSince1970, limit])
            return try rows.compactMap { try Self.session(from: $0, in: db) }
        } ?? []
    }

    /// The most recent session that ended before `date`.
    func lastSession(endingBefore date: Date) -> WorkSessionRecord? {
        read("lastSession") { db -> WorkSessionRecord? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT id, title, started_at, ended_at, apps, active_seconds FROM work_session
                WHERE ended_at < ? ORDER BY ended_at DESC LIMIT 1
                """, arguments: [date.timeIntervalSince1970]) else { return nil }
            return try Self.session(from: row, in: db)
        } ?? nil
    }

    // MARK: Row mapping

    static func visit(from row: Row) -> PageVisit? {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else { return nil }
        let start = Date(timeIntervalSince1970: row["timestamp"])
        let duration: Double = row["duration"] ?? 0
        let urlString: String? = row["url"]
        let key: String? = row["page_key"]
        return PageVisit(
            id: id,
            key: PageKey(rawValue: key ?? idString),
            application: row["application"],
            bundleIdentifier: row["bundle_id"],
            title: row["window_title"],
            url: urlString.flatMap(URL.init(string:)),
            start: start,
            end: start.addingTimeInterval(duration)
        )
    }

    static func bookmark(from row: Row) -> BookmarkRecord? {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else { return nil }
        let urlString: String? = row["url"]
        let reasons: String = row["reasons"]
        return BookmarkRecord(
            id: id,
            title: row["window_title"],
            url: urlString.flatMap(URL.init(string:)),
            application: row["application"],
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            score: row["score"],
            reasons: reasons.split(separator: ",").map(String.init)
        )
    }

    static func session(from row: Row, in db: Database) throws -> WorkSessionRecord? {
        let idString: String = row["id"]
        guard let id = UUID(uuidString: idString) else { return nil }
        let apps: String? = row["apps"]
        var record = WorkSessionRecord(
            id: id,
            title: row["title"],
            start: Date(timeIntervalSince1970: row["started_at"]),
            end: Date(timeIntervalSince1970: row["ended_at"]),
            applications: apps?.split(separator: "\n").map(String.init) ?? [],
            activeSeconds: row["active_seconds"]
        )
        record.bookmarks = try Row.fetchAll(db, sql: """
            SELECT o.id, o.window_title, o.url, o.application, o.timestamp, b.score, b.reasons
            FROM bookmark b JOIN observation o ON o.id = b.observation_id
            WHERE o.session_id = ? ORDER BY b.score DESC LIMIT 5
            """, arguments: [idString]).compactMap(bookmark(from:))
        record.topPages = try String.fetchAll(db, sql: """
            SELECT window_title FROM observation WHERE session_id = ? AND category = 'page' AND window_title IS NOT NULL
            GROUP BY window_title ORDER BY sum(duration) DESC LIMIT 5
            """, arguments: [idString])
        return record
    }
}
