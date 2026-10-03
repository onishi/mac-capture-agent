import Foundation

/// A remembered moment of what the user saw. Not persisted in v0.1.
///
/// When implemented, entries must only contain derived data (entities,
/// summary, embedding) — never raw screenshots — and honour `PrivacyPolicy`.
public struct VisualMemoryEntry: Sendable, Equatable {
    public let timestamp: Date
    public let application: String?
    public let windowTitle: String?
    public let url: URL?
    public let entities: [String]
    public let summary: String?
    public let embedding: [Float]?

    public init(timestamp: Date, application: String?, windowTitle: String?, url: URL?,
                entities: [String], summary: String?, embedding: [Float]?) {
        self.timestamp = timestamp
        self.application = application
        self.windowTitle = windowTitle
        self.url = url
        self.entities = entities
        self.summary = summary
        self.embedding = embedding
    }
}

/// Storage + semantic search for visual memory ("the blue car I saw yesterday").
public protocol VisualMemoryStore: Sendable {
    func remember(_ entry: VisualMemoryEntry) async
    func search(_ query: String, limit: Int) async -> [VisualMemoryEntry]
}

/// v0.1: remembers nothing.
public struct DisabledVisualMemoryStore: VisualMemoryStore {
    public init() {}
    public func remember(_ entry: VisualMemoryEntry) async {}
    public func search(_ query: String, limit: Int) async -> [VisualMemoryEntry] { [] }
}
