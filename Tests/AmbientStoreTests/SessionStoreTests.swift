import XCTest
import AmbientCore
@testable import AmbientStore

private struct NoEmbedding: TextEmbedding {
    func vector(for text: String, language: String) -> [Float]? { nil }
}

final class SessionStoreTests: XCTestCase {
    func makeStore(retentionDays: Int = 7) -> IntelStore {
        IntelStore(url: nil, retentionDays: retentionDays, userLanguage: "ja", embedding: NoEmbedding())
    }

    func visit(_ title: String, url: String? = nil, hoursAgo: Double, minutes: Double) -> PageVisit {
        let start = Date().addingTimeInterval(-hoursAgo * 3600)
        let parsed = url.flatMap(URL.init(string:))
        return PageVisit(key: PageKey(bundleIdentifier: "com.apple.Safari", windowTitle: title, url: parsed),
                         application: "Safari", bundleIdentifier: "com.apple.Safari", title: title, url: parsed,
                         start: start, end: start.addingTimeInterval(minutes * 60))
    }

    func testVisitsRevisitsAndBookmarks() async {
        let store = makeStore()
        let first = visit("Issue #32 · cinema", url: "https://github.com/x/cinema/issues/32", hoursAgo: 30, minutes: 4)
        let second = visit("Issue #32 · cinema", url: "https://github.com/x/cinema/issues/32", hoursAgo: 1, minutes: 6)
        await store.recordPageVisit(first)
        await store.recordPageVisit(second)

        let revisits = await store.visitCount(second.key, since: Date().addingTimeInterval(-7 * 86400), excluding: second.id)
        XCTAssertEqual(revisits, 1)

        let visits = await store.pageVisits(since: Date().addingTimeInterval(-2 * 86400))
        XCTAssertEqual(visits.map(\.id), [first.id, second.id])
        XCTAssertEqual(visits.last?.duration ?? 0, 360, accuracy: 1)
        XCTAssertEqual(visits.last?.url?.absoluteString, "https://github.com/x/cinema/issues/32")

        await store.saveBookmark(observationID: second.id, score: BookmarkScorer.score(PageActivity(focusSeconds: 400, copies: 1)))
        let bookmarks = await store.bookmarks(since: Date().addingTimeInterval(-86400))
        XCTAssertEqual(bookmarks.map(\.title), ["Issue #32 · cinema"])
        XCTAssertEqual(bookmarks.first?.reasons, ["dwell", "copy"])
    }

    func testBookmarksSurviveRetention() async {
        let store = makeStore(retentionDays: 1)
        let old = visit("Important spec", hoursAgo: 30, minutes: 10)
        let other = visit("Unimportant page", hoursAgo: 30, minutes: 1)
        await store.recordPageVisit(old)
        await store.recordPageVisit(other)
        await store.saveBookmark(observationID: old.id, score: BookmarkScore(value: 0.9, reasons: [.longRead]))
        await store.configure(retentionDays: 1, userLanguage: "ja")   // prunes
        let visits = await store.pageVisits(since: .distantPast)
        XCTAssertEqual(visits.map(\.title), ["Important spec"])
    }

    func testSessionsRoundTrip() async {
        let store = makeStore()
        let a = visit("cinema scraper design", hoursAgo: 26, minutes: 20)
        let b = visit("cinema scraper tests", hoursAgo: 25.6, minutes: 15)
        await store.recordPageVisit(a)
        await store.recordPageVisit(b)
        await store.saveBookmark(observationID: b.id, score: BookmarkScore(value: 0.8, reasons: [.copied]))
        let drafts = WorkSessionClusterer().cluster([a, b])
        XCTAssertEqual(drafts.count, 1)
        await store.saveSessions([(drafts[0], "Cinema scraper")])

        let name = await store.sessionName(drafts[0].id)
        XCTAssertEqual(name, "Cinema scraper")
        let sessions = await store.sessions(since: Date().addingTimeInterval(-2 * 86400))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].bookmarks.map(\.title), ["cinema scraper tests"])
        XCTAssertEqual(sessions[0].topPages.first, "cinema scraper design")
        XCTAssertEqual(sessions[0].activeSeconds, 35 * 60, accuracy: 1)

        let last = await store.lastSession(endingBefore: Date())
        XCTAssertEqual(last?.title, "Cinema scraper")
        let none = await store.lastSession(endingBefore: Date().addingTimeInterval(-3 * 86400))
        XCTAssertNil(none)

        await store.removeAll()
        let cleared = await store.sessions(since: .distantPast)
        XCTAssertTrue(cleared.isEmpty)
    }
}

final class RelatedPagesTests: XCTestCase {
    func testRelatedPagesByTitleKeywords() async {
        let store = IntelStore(url: nil, retentionDays: 30, userLanguage: "ja", embedding: RelatedNoEmbedding())
        func visit(_ title: String, _ url: String, daysAgo: Double) -> PageVisit {
            let start = Date().addingTimeInterval(-daysAgo * 86400)
            let parsed = URL(string: url)
            return PageVisit(key: PageKey(bundleIdentifier: "com.apple.Safari", windowTitle: title, url: parsed), application: "Safari",
                             bundleIdentifier: "com.apple.Safari", title: title, url: parsed, start: start, end: start.addingTimeInterval(120))
        }
        await store.recordPageVisit(visit("Central bank holds interest rates", "https://www.reuters.com/a", daysAgo: 3))
        await store.recordPageVisit(visit("Weather in Tokyo", "https://example.com/w", daysAgo: 1))
        let related = await store.relatedPages(keywords: ["interest", "rates"], excludingURL: URL(string: "https://www.reuters.com/b"),
                                               since: Date().addingTimeInterval(-30 * 86400))
        XCTAssertEqual(related.map(\.title), ["Central bank holds interest rates"])
        let excluded = await store.relatedPages(keywords: ["interest"], excludingURL: URL(string: "https://www.reuters.com/a"),
                                                since: Date().addingTimeInterval(-30 * 86400))
        XCTAssertTrue(excluded.isEmpty)
    }
}

private struct RelatedNoEmbedding: TextEmbedding {
    func vector(for text: String, language: String) -> [Float]? { nil }
}
