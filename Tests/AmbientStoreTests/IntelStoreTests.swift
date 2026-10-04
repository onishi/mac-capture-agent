import XCTest
import AmbientCore
@testable import AmbientStore

/// Deterministic embedding for tests: one dimension per known word.
private struct StubEmbedding: TextEmbedding {
    func vector(for text: String, language: String) -> [Float]? {
        ["美術館", "電車", "空港"].map { text.contains($0) ? 1 : 0 }
    }
}

final class IntelStoreTests: XCTestCase {
    func makeStore(retentionDays: Int = 7) -> IntelStore {
        IntelStore(url: nil, retentionDays: retentionDays, userLanguage: "ja", embedding: StubEmbedding())
    }

    func entry(_ original: String, _ translation: String, language: String = "fr", hoursAgo: Double = 1,
               kind: VisualMemoryEntry.Kind = .translation) -> VisualMemoryEntry {
        VisualMemoryEntry(timestamp: Date().addingTimeInterval(-hoursAgo * 3600), kind: kind, application: "Safari",
                          bundleIdentifier: "com.apple.Safari", windowTitle: "Page", sourceLanguage: language,
                          targetLanguage: "ja", original: original, translation: translation,
                          features: PersonalizationFeatures(action: .translate, language: language, bundleIdentifier: "com.apple.Safari"))
    }

    func testRememberSearchAndCount() async {
        let store = makeStore()
        let isAvailable = await store.isAvailable
        XCTAssertTrue(isAvailable)
        await store.remember(entry("Le musée est fermé le lundi.", "美術館は月曜日休館です。"))
        await store.remember(entry("Der Zug fällt aus.", "電車は運休です。", language: "de"))
        let count = await store.count()
        XCTAssertEqual(count, 2)

        let museum = await store.search("美術館", limit: 10)
        XCTAssertEqual(museum.first?.entry.sourceLanguage, "fr")
        XCTAssertEqual(museum.first?.entry.features?.language, "fr", "features round-trip")
        XCTAssertNotNil(museum.first?.entry.embedding, "embedding stored")

        let german = await store.search("ドイツ語", limit: 10)
        XCTAssertEqual(german.map(\.entry.original), ["Der Zug fällt aus."])
    }

    func testDuplicateTextRefreshesInsteadOfAdding() async {
        let store = makeStore()
        await store.remember(entry("Bonjour à tous", "皆さんこんにちは", hoursAgo: 5))
        await store.remember(entry("Bonjour à tous", "皆さんこんにちは", hoursAgo: 1))
        let count = await store.count()
        XCTAssertEqual(count, 1)
    }

    func testRetentionPrunes() async {
        let store = makeStore(retentionDays: 1)
        await store.remember(entry("Ancien texte ici", "古い文章", hoursAgo: 30))
        await store.remember(entry("Nouveau texte ici", "新しい文章", hoursAgo: 1))
        let count = await store.count()
        XCTAssertEqual(count, 1)
        let old = await store.search("古い", limit: 10)
        XCTAssertTrue(old.isEmpty)
    }

    func testBriefingUpdateIsSearchable() async {
        let store = makeStore()
        let item = entry("Le musée est fermé.", "美術館は休館です。")
        await store.remember(item)
        await store.updateBriefing("訪問前に営業日を確認", for: item.id)
        let results = await store.search("営業日", limit: 5)
        XCTAssertEqual(results.first?.entry.briefing, "訪問前に営業日を確認")
    }

    func testFullTextQueryMatchesJapaneseSubstrings() async {
        let store = makeStore()
        await store.remember(entry("Le musée est fermé.", "美術館は休館です。", hoursAgo: 48))
        let results = await store.search("休館です", limit: 5)
        XCTAssertEqual(results.count, 1)
    }

    func testRemoveAll() async {
        let store = makeStore()
        await store.remember(entry("Le musée est fermé.", "美術館は休館です。"))
        await store.removeAll()
        let count = await store.count()
        XCTAssertEqual(count, 0)
        let results = await store.search("美術館", limit: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testEntitiesAndReappearance() async {
        let store = makeStore()
        let first = entry("OpenAI annonce un modèle.", "OpenAI がモデルを発表", hoursAgo: 72)
        let second = entry("OpenAI publie une mise à jour.", "OpenAI が更新を公開", hoursAgo: 0)
        let openAI = ExtractedEntity(type: .organization, name: "OpenAI")
        await store.remember(first)
        await store.recordEntities([openAI], observationID: first.id)
        await store.remember(second)
        await store.recordEntities([openAI], observationID: second.id)

        let seen = await store.lastSeen([openAI], before: second.timestamp, excluding: second.id)
        XCTAssertEqual(seen?.timeIntervalSince1970 ?? 0, first.timestamp.timeIntervalSince1970, accuracy: 1)
        let never = await store.lastSeen([ExtractedEntity(type: .person, name: "Nobody")], before: Date(), excluding: nil)
        XCTAssertNil(never)
    }

    func testKnowledgeCacheAndKnownTerms() async {
        let store = makeStore()
        var cached = await store.knowledge(forTerm: "rag")
        XCTAssertNil(cached)
        await store.saveKnowledge(term: "RAG", summary: "外部情報を検索して回答に使う手法", detail: "Retrieval-Augmented Generation", source: "foundation-models")
        cached = await store.knowledge(forTerm: "rag")
        XCTAssertEqual(cached?.detail, "Retrieval-Augmented Generation")

        let expired = await store.knowledge(forTerm: "rag", now: Date().addingTimeInterval(31 * 24 * 3600))
        XCTAssertNil(expired, "30-day cache")

        var skip = await store.shouldSkipTerm("rag")
        XCTAssertFalse(skip)
        for _ in 0..<3 { await store.noteTermShown("RAG") }
        skip = await store.shouldSkipTerm("rag")
        XCTAssertTrue(skip, "explained three times")

        await store.markTermKnown("CRDT")
        skip = await store.shouldSkipTerm("crdt")
        XCTAssertTrue(skip, "marked known")
    }

    func testLegacyJSONImport() async throws {
        var index = VisualMemoryIndex()
        index.add(entry("Le musée est fermé.", "美術館は休館です。"), now: Date())
        index.add(entry("Der Zug fällt aus.", "電車は運休です。", language: "de"), now: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString).json")
        try JSONEncoder().encode(index).write(to: url)

        let store = makeStore()
        let imported = await store.importLegacyJSON(at: url)
        XCTAssertEqual(imported, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "legacy file removed")
        let count = await store.count()
        XCTAssertEqual(count, 2)
        let none = await store.importLegacyJSON(at: url)
        XCTAssertEqual(none, 0)
    }

    func testPersistsAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("intel-\(UUID().uuidString).sqlite")
        do {
            let store = IntelStore(url: url, retentionDays: 7, userLanguage: "ja", embedding: StubEmbedding())
            await store.remember(entry("Le musée est fermé.", "美術館は休館です。"))
        }
        let reopened = IntelStore(url: url, retentionDays: 7, userLanguage: "ja", embedding: StubEmbedding())
        let count = await reopened.count()
        XCTAssertEqual(count, 1)
        try? FileManager.default.removeItem(at: url)
    }

    func testVectorCoding() {
        let vector: [Float] = [0.25, -1, 3.5]
        XCTAssertEqual(VectorCoding.vector(from: VectorCoding.data(from: vector)), vector)
    }
}

final class GenericKnowledgeTests: XCTestCase {
    func testPersonKnowledgeIsSeparateFromTerms() async {
        let store = IntelStore(url: nil, retentionDays: 7, userLanguage: "ja", embedding: StubEmbeddingForKnowledge())
        let cate = ExtractedEntity(type: .person, name: "Cate Blanchett")
        await store.saveKnowledge(entity: cate, summary: "Actor", detail: "TÁR\nCarol", source: "gemini")
        let person = await store.knowledge(type: .person, canonical: cate.canonicalName)
        XCTAssertEqual(person?.summary, "Actor")
        let asTerm = await store.knowledge(forTerm: cate.canonicalName)
        XCTAssertNil(asTerm)
    }
}

private struct StubEmbeddingForKnowledge: TextEmbedding {
    func vector(for text: String, language: String) -> [Float]? { nil }
}
