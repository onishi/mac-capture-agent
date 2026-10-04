import Foundation

/// A remembered piece of intel the user saw. Derived data only — never a
/// screenshot. Only items that were actually surfaced in the HUD are stored.
public struct VisualMemoryEntry: Sendable, Equatable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        case translation
        case explanation
        case errorAnalysis
        case codeSummary
        case identification
        case publicFigure
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let application: String?
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let url: URL?
    public let sourceLanguage: String?
    public let targetLanguage: String?
    public let original: String
    public let translation: String
    public var briefing: String?
    public var entities: [String]
    /// Sentence embedding of the translation (user's language), for semantic search.
    public var embedding: [Float]?
    public let features: PersonalizationFeatures?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: Kind = .translation,
        application: String?,
        bundleIdentifier: String?,
        windowTitle: String?,
        url: URL? = nil,
        sourceLanguage: String?,
        targetLanguage: String?,
        original: String,
        translation: String,
        briefing: String? = nil,
        entities: [String] = [],
        embedding: [Float]? = nil,
        features: PersonalizationFeatures? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.application = application
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.original = original
        self.translation = translation
        self.briefing = briefing
        self.entities = entities
        self.embedding = embedding
        self.features = features
    }

    /// Text used for keyword search.
    var searchableText: String {
        [original, translation, briefing ?? "", application ?? "", windowTitle ?? "", entities.joined(separator: " ")]
            .joined(separator: "\n")
            .lowercased()
    }
}

public struct MemorySearchResult: Sendable, Equatable, Identifiable {
    public let entry: VisualMemoryEntry
    public let score: Double
    public var id: UUID { entry.id }
}

/// Storage + search for visual memory ("the French notice I saw yesterday").
public protocol VisualMemoryStore: Sendable {
    func remember(_ entry: VisualMemoryEntry) async
    func updateBriefing(_ briefing: String, for id: UUID) async
    func search(_ query: String, limit: Int) async -> [MemorySearchResult]
    func count() async -> Int
    func removeAll() async
}

/// Remembers nothing (memory disabled).
public struct DisabledVisualMemoryStore: VisualMemoryStore {
    public init() {}
    public func remember(_ entry: VisualMemoryEntry) async {}
    public func updateBriefing(_ briefing: String, for id: UUID) async {}
    public func search(_ query: String, limit: Int) async -> [MemorySearchResult] { [] }
    public func count() async -> Int { 0 }
    public func removeAll() async {}
}

/// Turns text into a vector for semantic search (NLEmbedding in the app).
public protocol TextEmbedding: Sendable {
    func vector(for text: String, language: String) -> [Float]?
}
