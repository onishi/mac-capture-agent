import XCTest
@testable import AmbientCore

final class MemoryQueryParserTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
    // 2026-10-04 15:00 JST
    let now = Date(timeIntervalSince1970: 1_791_100_800)

    func testJapaneseDateAndLanguage() throws {
        let query = MemoryQueryParser.parse("昨日見ていたフランス語の美術館", now: now, calendar: calendar)
        XCTAssertEqual(query.language, "fr")
        XCTAssertEqual(query.text, "美術館")
        let range = try XCTUnwrap(query.dateRange)
        XCTAssertEqual(range.duration, 24 * 60 * 60)
        XCTAssertEqual(range.end, calendar.startOfDay(for: now))
    }

    func testDayBeforeYesterdayIsNotYesterday() throws {
        let query = MemoryQueryParser.parse("一昨日の英語", now: now, calendar: calendar)
        XCTAssertEqual(query.language, "en")
        let range = try XCTUnwrap(query.dateRange)
        XCTAssertEqual(range.end, calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        XCTAssertEqual(query.text, "")
    }

    func testEnglishQuery() {
        let query = MemoryQueryParser.parse("the German train notice I saw today", now: now, calendar: calendar)
        XCTAssertEqual(query.language, "de")
        XCTAssertEqual(query.dateRange?.end, now)
        XCTAssertEqual(query.text, "train notice")
    }

    func testPlainKeywords() {
        let query = MemoryQueryParser.parse("museum hours", now: now, calendar: calendar)
        XCTAssertEqual(query, MemoryQuery(text: "museum hours"))
        XCTAssertFalse(query.hasFilters)
    }

    func testRecentIsTwoHours() {
        let query = MemoryQueryParser.parse("さっきの", now: now, calendar: calendar)
        XCTAssertEqual(query.dateRange?.duration, 2 * 60 * 60)
        XCTAssertEqual(query.text, "")
    }
}

final class VisualMemoryIndexTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_100_800)

    func entry(_ original: String, _ translation: String, language: String = "fr", hoursAgo: Double = 1, embedding: [Float]? = nil) -> VisualMemoryEntry {
        VisualMemoryEntry(timestamp: now.addingTimeInterval(-hoursAgo * 3600), application: "Safari", bundleIdentifier: "com.apple.Safari",
                          windowTitle: "Page", sourceLanguage: language, targetLanguage: "ja", original: original, translation: translation,
                          embedding: embedding)
    }

    func testRetentionAndCapacity() {
        var index = VisualMemoryIndex(retention: 24 * 3600, maximumEntries: 2)
        index.add(entry("a a a", "あ", hoursAgo: 30), now: now)
        XCTAssertTrue(index.entries.isEmpty, "older than retention")
        index.add(entry("one", "一", hoursAgo: 3), now: now)
        index.add(entry("two", "二", hoursAgo: 2), now: now)
        index.add(entry("three", "三", hoursAgo: 1), now: now)
        XCTAssertEqual(index.entries.map(\.original), ["three", "two"], "newest kept")
    }

    func testSameTextIsDeduplicated() {
        var index = VisualMemoryIndex()
        index.add(entry("Bonjour à tous", "皆さんこんにちは", hoursAgo: 5), now: now)
        index.add(entry("Bonjour à tous", "皆さんこんにちは", hoursAgo: 1), now: now)
        XCTAssertEqual(index.entries.count, 1)
        XCTAssertEqual(index.entries.first?.timestamp, now.addingTimeInterval(-3600))
    }

    func testKeywordSearchMatchesTranslationAndOriginal() {
        var index = VisualMemoryIndex()
        index.add(entry("Le musée est fermé le lundi.", "美術館は月曜日休館です。"), now: now)
        index.add(entry("Der Zug fällt aus.", "電車は運休です。", language: "de"), now: now)
        XCTAssertEqual(index.search(MemoryQuery(text: "美術館"), queryEmbedding: nil, now: now, limit: 5).map(\.entry.sourceLanguage), ["fr"])
        XCTAssertEqual(index.search(MemoryQuery(text: "zug"), queryEmbedding: nil, now: now, limit: 5).count, 1)
        XCTAssertTrue(index.search(MemoryQuery(text: "airport"), queryEmbedding: nil, now: now, limit: 5).isEmpty)
    }

    func testCJKBigramPartialMatch() {
        XCTAssertEqual(VisualMemoryIndex.keywordScore("美術館の休み", in: "美術館は月曜日休館です"), 0.4, accuracy: 0.01)
    }

    func testFiltersWithoutText() {
        var index = VisualMemoryIndex()
        index.add(entry("Le musée", "美術館", language: "fr", hoursAgo: 30), now: now)
        index.add(entry("The museum", "博物館", language: "en", hoursAgo: 1), now: now)
        let yesterday = DateInterval(start: now.addingTimeInterval(-48 * 3600), end: now.addingTimeInterval(-24 * 3600))
        let results = index.search(MemoryQuery(text: "", dateRange: yesterday), queryEmbedding: nil, now: now, limit: 5)
        XCTAssertEqual(results.map(\.entry.original), ["Le musée"])
        XCTAssertEqual(index.search(MemoryQuery(text: "", language: "en"), queryEmbedding: nil, now: now, limit: 5).map(\.entry.original), ["The museum"])
    }

    func testFilteredResultsRankRelevantFirst() {
        var index = VisualMemoryIndex()
        index.add(entry("Le train est en retard.", "電車が遅れています。", hoursAgo: 1), now: now)
        index.add(entry("Le musée est fermé.", "美術館は休館です。", hoursAgo: 2), now: now)
        let results = index.search(MemoryQuery(text: "美術館", language: "fr"), queryEmbedding: nil, now: now, limit: 5)
        XCTAssertEqual(results.first?.entry.original, "Le musée est fermé.")
        XCTAssertEqual(results.count, 2, "filter matches are kept, ranked below")
    }

    func testSemanticSearch() {
        var index = VisualMemoryIndex()
        index.add(entry("Le musée est fermé.", "美術館は休館です。", embedding: [1, 0, 0]), now: now)
        index.add(entry("Le train est en retard.", "電車が遅れています。", embedding: [0, 1, 0]), now: now)
        let results = index.search(MemoryQuery(text: "ギャラリー"), queryEmbedding: [0.9, 0.1, 0], now: now, limit: 5)
        XCTAssertEqual(results.map(\.entry.original), ["Le musée est fermé."])
        XCTAssertEqual(VisualMemoryIndex.semanticScore([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(VisualMemoryIndex.semanticScore([1, 0], [0, 1]), 0)
        XCTAssertEqual(VisualMemoryIndex.semanticScore([1, 0], [1, 0, 0]), 0, "dimension mismatch")
    }

    func testBriefingUpdateAndCodable() throws {
        var index = VisualMemoryIndex()
        let item = entry("Le musée est fermé.", "美術館は休館です。")
        index.add(item, now: now)
        index.updateBriefing("訪問前に確認", for: item.id)
        XCTAssertEqual(index.search(MemoryQuery(text: "訪問"), queryEmbedding: nil, now: now, limit: 1).first?.entry.briefing, "訪問前に確認")
        let data = try JSONEncoder().encode(index)
        XCTAssertEqual(try JSONDecoder().decode(VisualMemoryIndex.self, from: data), index)
    }
}
