import Foundation
import GRDB
#if canImport(AmbientCore)
import AmbientCore
#endif

/// The app's SQLite database (GRDB). Holds derived data only — never images.
/// Schema: docs/ARCHITECTURE.md §5.2.
struct IntelDatabase: Sendable {
    let writer: DatabaseQueue

    /// Opens (and migrates) the database at `url`, or an in-memory one when `url` is nil.
    init(url: URL?) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            writer = try DatabaseQueue(path: url.path, configuration: configuration)
            var resourceURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? resourceURL.setResourceValues(values)
        } else {
            writer = try DatabaseQueue(configuration: configuration)
        }
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE observation (
                  id TEXT PRIMARY KEY,
                  timestamp REAL NOT NULL,
                  application TEXT,
                  bundle_id TEXT,
                  window_title TEXT,
                  url TEXT,
                  screen_id INTEGER,
                  region_x REAL, region_y REAL, region_w REAL, region_h REAL,
                  category TEXT NOT NULL,
                  confidence REAL NOT NULL,
                  text TEXT
                );
                CREATE INDEX observation_time ON observation(timestamp);

                CREATE TABLE intel (
                  id TEXT PRIMARY KEY,
                  observation_id TEXT NOT NULL REFERENCES observation(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL,
                  title TEXT,
                  body TEXT NOT NULL,
                  briefing TEXT,
                  source_lang TEXT,
                  target_lang TEXT,
                  importance REAL NOT NULL,
                  feedback TEXT,
                  features TEXT
                );
                CREATE INDEX intel_observation ON intel(observation_id);

                CREATE TABLE entity (
                  id TEXT PRIMARY KEY,
                  type TEXT NOT NULL,
                  name TEXT NOT NULL,
                  canonical_name TEXT NOT NULL,
                  metadata TEXT,
                  known INTEGER NOT NULL DEFAULT 0,
                  shown_count INTEGER NOT NULL DEFAULT 0,
                  UNIQUE(type, canonical_name)
                );

                CREATE TABLE observation_entity (
                  observation_id TEXT NOT NULL REFERENCES observation(id) ON DELETE CASCADE,
                  entity_id TEXT NOT NULL REFERENCES entity(id) ON DELETE CASCADE,
                  confidence REAL NOT NULL,
                  PRIMARY KEY (observation_id, entity_id)
                );
                CREATE INDEX observation_entity_entity ON observation_entity(entity_id);

                CREATE TABLE knowledge (
                  entity_id TEXT PRIMARY KEY REFERENCES entity(id) ON DELETE CASCADE,
                  summary TEXT NOT NULL,
                  detail TEXT,
                  source TEXT NOT NULL,
                  updated_at REAL NOT NULL,
                  expires_at REAL NOT NULL
                );

                CREATE TABLE embedding (
                  owner_type TEXT NOT NULL,
                  owner_id TEXT NOT NULL,
                  model TEXT NOT NULL,
                  vector BLOB NOT NULL,
                  PRIMARY KEY (owner_type, owner_id, model)
                );

                CREATE VIRTUAL TABLE intel_fts USING fts5(
                  intel_id UNINDEXED, original, body, briefing, context,
                  tokenize = 'trigram'
                );
                """)
        }
        migrator.registerMigration("v2-sessions") { db in
            try db.execute(sql: """
                ALTER TABLE observation ADD COLUMN session_id TEXT;
                ALTER TABLE observation ADD COLUMN duration REAL;
                ALTER TABLE observation ADD COLUMN page_key TEXT;
                CREATE INDEX observation_page ON observation(page_key);
                CREATE INDEX observation_category_time ON observation(category, timestamp);

                CREATE TABLE work_session (
                  id TEXT PRIMARY KEY,
                  title TEXT,
                  started_at REAL NOT NULL,
                  ended_at REAL NOT NULL,
                  apps TEXT,
                  summary TEXT,
                  active_seconds REAL NOT NULL DEFAULT 0
                );

                CREATE TABLE bookmark (
                  observation_id TEXT PRIMARY KEY REFERENCES observation(id) ON DELETE CASCADE,
                  score REAL NOT NULL,
                  reasons TEXT NOT NULL
                );
                """)
        }
        return migrator
    }
}

enum VectorCoding {
    static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func vector(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * MemoryLayout<Float>.size, as: Float.self) }
        }
    }
}
