import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

final class URLSanitizerTests: XCTestCase {
    func testDropsQueryFragmentAndCredentials() {
        XCTAssertEqual(URLSanitizer.sanitize("https://user:pw@GitHub.com/onishi/repo/issues/32?token=abc#top")?.absoluteString,
                       "https://github.com/onishi/repo/issues/32")
        XCTAssertNil(URLSanitizer.sanitize("file:///Users/me/secret.txt"))
        XCTAssertNil(URLSanitizer.sanitize("javascript:alert(1)"))
        XCTAssertNil(URLSanitizer.sanitize("not a url"))
    }

    func testDisplayHost() {
        XCTAssertEqual(URLSanitizer.displayHost(URL(string: "https://www.example.com/a")!), "example.com")
    }

    func testPageKey() {
        let url = URL(string: "https://github.com/a")
        XCTAssertEqual(PageKey(bundleIdentifier: "com.apple.Safari", windowTitle: "x", url: url).value, "url:https://github.com/a")
        XCTAssertEqual(PageKey(bundleIdentifier: "com.apple.Terminal", windowTitle: "zsh  — 80×24", url: nil).value, "win:com.apple.Terminal|zsh — 80×24")
    }
}

final class BookmarkScorerTests: XCTestCase {
    func testQuickVisitIsNotABookmark() {
        XCTAssertFalse(BookmarkScorer.score(PageActivity(focusSeconds: 20)).isBookmark)
        XCTAssertFalse(BookmarkScorer.score(PageActivity(focusSeconds: 120)).isBookmark)
    }

    func testLongReadWithCopyIsABookmark() {
        let score = BookmarkScorer.score(PageActivity(focusSeconds: 400, copies: 1))
        XCTAssertTrue(score.isBookmark)
        XCTAssertEqual(score.reasons, [.longRead, .copied])
    }

    func testRevisitsAndPointerDwellAddUp() {
        let score = BookmarkScorer.score(PageActivity(focusSeconds: 200, revisits: 3, pointerDwells: 2))
        XCTAssertTrue(score.isBookmark)
        XCTAssertTrue(score.reasons.contains(.revisited))
        XCTAssertTrue(score.reasons.contains(.pointerFocus))
        XCTAssertLessThanOrEqual(BookmarkScorer.score(PageActivity(focusSeconds: 9_999, revisits: 99, copies: 99, pointerDwells: 99, intelShown: 99)).value, 1)
    }
}

final class WorkSessionTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_791_100_800)

    func visit(_ title: String, app: String = "Safari", bundle: String = "com.apple.Safari", url: String? = nil, at minute: Double, for minutes: Double) -> PageVisit {
        PageVisit(key: PageKey(rawValue: title), application: app, bundleIdentifier: bundle, title: title,
                  url: url.flatMap(URL.init(string:)), start: t0.addingTimeInterval(minute * 60), end: t0.addingTimeInterval((minute + minutes) * 60))
    }

    func testRelatedVisitsAcrossAppsFormOneSession() {
        let sessions = WorkSessionClusterer().cluster([
            visit("Cinema timetable scraper · Issue #32", url: "https://github.com/x/cinema/issues/32", at: 0, for: 5),
            visit("cinema scraper – Slack", app: "Slack", bundle: "com.tinyspeck.slackmacgap", at: 5, for: 3),
            visit("scraper.ts — cinema", app: "Code", bundle: "com.microsoft.VSCode", at: 8, for: 20),
            visit("zsh — cinema", app: "Terminal", bundle: "com.apple.Terminal", at: 28, for: 5)
        ])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].applications, ["Safari", "Slack", "Code", "Terminal"])
        XCTAssertTrue(sessions[0].keywords().contains("cinema"))
        XCTAssertEqual(sessions[0].activeDuration, 33 * 60, accuracy: 1)
    }

    func testIdleGapSplits() {
        let sessions = WorkSessionClusterer().cluster([
            visit("Cinema scraper", at: 0, for: 10),
            visit("Cinema scraper", at: 45, for: 10)
        ])
        XCTAssertEqual(sessions.count, 2)
    }

    func testShortDetourStaysLongTopicChangeSplits() {
        let short = WorkSessionClusterer().cluster([
            visit("Cinema scraper design", at: 0, for: 10),
            visit("Weather forecast Tokyo", at: 10, for: 2),
            visit("Cinema scraper tests", at: 12, for: 10)
        ])
        XCTAssertEqual(short.count, 1, "short detour stays in the session")

        let long = WorkSessionClusterer().cluster([
            visit("Cinema scraper design", at: 0, for: 10),
            visit("Hiring pipeline candidates", at: 10, for: 15),
            visit("Hiring interview schedule", at: 25, for: 10)
        ])
        XCTAssertEqual(long.count, 2)
        XCTAssertTrue(long[1].keywords().contains("hiring"))
    }

    func testDailySummaryAndResumePolicy() {
        let themes = DailySummary.themes([("Cloudflare", 1800.0), ("Cloudflare", 720.0), ("採用関連", 1860.0), ("noise", 60.0)])
        XCTAssertEqual(themes, [DailySummary.Theme(name: "Cloudflare", minutes: 42), DailySummary.Theme(name: "採用関連", minutes: 31)])

        let now = t0
        XCTAssertTrue(ResumePolicy.shouldOffer(lastSessionEnd: now.addingTimeInterval(-10 * 3600), now: now, alreadyOfferedToday: false))
        XCTAssertFalse(ResumePolicy.shouldOffer(lastSessionEnd: now.addingTimeInterval(-3600), now: now, alreadyOfferedToday: false), "too recent")
        XCTAssertFalse(ResumePolicy.shouldOffer(lastSessionEnd: now.addingTimeInterval(-10 * 86400), now: now, alreadyOfferedToday: false), "too old")
        XCTAssertFalse(ResumePolicy.shouldOffer(lastSessionEnd: now.addingTimeInterval(-10 * 3600), now: now, alreadyOfferedToday: true))
    }

    func testQRContent() {
        XCTAssertEqual(QRContent.display("https://example.com/menu?table=3")?.text, "example.com/menu")
        XCTAssertEqual(QRContent.display("https://example.com/")?.isURL, true)
        XCTAssertEqual(QRContent.display("WIFI:S:cafe;T:WPA;;")?.isURL, false)
        XCTAssertNil(QRContent.display("  "))
    }
}

final class InterestRegionSchedulerTests: XCTestCase {
    func testPriorityRegionIsAnalyzedWithoutWaitingForSettle() {
        var scheduler = AnalysisScheduler()
        let busy = ChangedRegion(rect: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), confidence: 1)
        _ = scheduler.ingest([busy], at: 0)
        _ = scheduler.ingest([], at: 0.5)          // analyzed
        let interest = ChangedRegion(rect: CGRect(x: 0.5, y: 0.5, width: 0.3, height: 0.2), confidence: 1)
        scheduler.prioritize(interest, at: 0.7)
        XCTAssertNil(scheduler.ingest([busy], at: 0.8), "respects the OCR interval")
        let result = scheduler.ingest([busy], at: 1.6)
        XCTAssertEqual(result?.contains { $0.rect.intersects(interest.rect) }, true, "analyzed while still changing")
    }
}

final class SessionNameSanitizerTests: XCTestCase {
    func testSanitize() {
        XCTAssertEqual(SessionNameSanitizer.sanitize("「映画時刻表機能の開発」。\n補足"), "映画時刻表機能の開発")
        XCTAssertNil(SessionNameSanitizer.sanitize("  "))
        XCTAssertEqual(SessionNameSanitizer.sanitize(String(repeating: "a", count: 100))?.count, SessionNameSanitizer.maximumLength)
    }
}
