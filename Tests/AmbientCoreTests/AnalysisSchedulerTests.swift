import XCTest
@testable import AmbientCore

final class AnalysisSchedulerTests: XCTestCase {
    let region = ChangedRegion(rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1), confidence: 0.8)

    func testNothingHappensWithoutChanges() {
        var scheduler = AnalysisScheduler()
        XCTAssertNil(scheduler.ingest([], at: 0))
        XCTAssertNil(scheduler.ingest([], at: 1))
    }

    func testAnalyzesOnceTheScreenSettles() {
        var scheduler = AnalysisScheduler()
        XCTAssertNil(scheduler.ingest([region], at: 0), "still changing")
        XCTAssertEqual(scheduler.ingest([], at: 0.5), [region], "settled")
        XCTAssertNil(scheduler.ingest([], at: 1.0), "nothing pending")
    }

    func testAnalyzesContinuousChangesAfterMaximumAge() {
        var scheduler = AnalysisScheduler()
        XCTAssertNil(scheduler.ingest([region], at: 0))
        XCTAssertNil(scheduler.ingest([region], at: 1))
        XCTAssertNotNil(scheduler.ingest([region], at: 2))
    }

    func testRespectsMinimumInterval() {
        var scheduler = AnalysisScheduler()
        _ = scheduler.ingest([region], at: 0)
        XCTAssertNotNil(scheduler.ingest([], at: 0.5))
        _ = scheduler.ingest([region], at: 0.6)
        XCTAssertNil(scheduler.ingest([], at: 1.0), "only 0.5s since last analysis")
        XCTAssertNotNil(scheduler.ingest([], at: 1.5))
    }

    func testLargeCoverageAnalyzesWholeScreen() {
        var scheduler = AnalysisScheduler()
        let big = ChangedRegion(rect: CGRect(x: 0, y: 0, width: 0.8, height: 0.8), confidence: 0.9)
        _ = scheduler.ingest([big], at: 0)
        XCTAssertEqual(scheduler.ingest([], at: 0.5)?.first?.rect, .unit)
    }

    func testLimitsNumberOfRegions() {
        var scheduler = AnalysisScheduler()
        let regions = (0..<8).map { i in
            ChangedRegion(rect: CGRect(x: 0.05, y: Double(i) * 0.12, width: 0.05 + Double(i) * 0.01, height: 0.02), confidence: 0.5)
        }
        _ = scheduler.ingest(regions, at: 0)
        let selected = scheduler.ingest([], at: 0.5) ?? []
        XCTAssertEqual(selected.count, 4)
        XCTAssertEqual(selected.first?.rect.width ?? 0, 0.12, accuracy: 0.0001, "largest first")
    }
}
