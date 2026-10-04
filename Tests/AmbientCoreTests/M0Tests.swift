import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

final class PauseScheduleTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testEveningPauseResumesNextMorning() {
        XCTAssertEqual(PauseSchedule.untilTomorrow(from: date(4, 22, 30), calendar: calendar), date(5, 6))
        XCTAssertEqual(PauseSchedule.untilTomorrow(from: date(4, 10), calendar: calendar), date(5, 6))
    }

    func testSmallHoursPauseResumesSameMorning() {
        XCTAssertEqual(PauseSchedule.untilTomorrow(from: date(5, 2), calendar: calendar), date(5, 6))
    }
}

final class RouterDecisionTests: XCTestCase {
    func testDecisionExposesCandidatesAndSelection() {
        let router = AIRouter(detector: ForeignTextDetector(
            identifier: StubLanguageIdentifier(fallback: LanguageGuess(code: "fr", confidence: 0.95)),
            configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")
        ))
        let ctx = context([textRegion("Bonjour à tous"), textRegion("Nous sommes heureux de vous accueillir ici.", y: 0.6)])
        let decision = router.decide(ctx)
        XCTAssertEqual(decision.candidates.count, 2)
        XCTAssertEqual(decision.selected, router.route(ctx))
        XCTAssertEqual(decision.selected.payload, "Nous sommes heureux de vous accueillir ici.")
        XCTAssertEqual(router.decide(context([])).selected, .ignore)
    }
}

final class DiagnosticsTests: XCTestCase {
    func testCandidateLabels() {
        XCTAssertEqual(PipelineDiagnostics.Candidate(action: .translate, importance: 0.824, region: nil, selected: true).label, "TRANSLATE 0.82 ✓")
        XCTAssertEqual(PipelineDiagnostics.Candidate(action: .translate, importance: 0.61, region: nil, selected: false).label, "TRANSLATE 0.61")
        XCTAssertEqual(PipelineDiagnostics.Candidate(action: .translate, importance: 0.9, region: nil, selected: true, suppressedByCooldown: true).label, "TRANSLATE 0.90 COOLDOWN")
    }

    func testTimingsAreOrderedAndRounded() {
        let text = PipelineCounters.formatTimings(["translate": 80.4, "detect": 1.6, "ocr": 140, "extra": 3])
        XCTAssertEqual(text, "DETECT 2ms · OCR 140ms · TRANSLATE 80ms · EXTRA 3ms")
    }

    func testCountersSummaryHasNoText() {
        var counters = PipelineCounters()
        counters.hudsShown = 2
        XCTAssertTrue(counters.summary.contains("HUD 2"))
    }
}

final class HUDGrowTests: XCTestCase {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 775)

    func testGrowKeepsTopEdge() {
        let frame = CGRect(x: 100, y: 400, width: 300, height: 120)
        let grown = HUDPlacement().grow(frame, byHeight: 30, within: visible)
        XCTAssertEqual(grown.maxY, frame.maxY)
        XCTAssertEqual(grown.height, 150)
    }

    func testGrowShiftsUpOnlyWhenNeeded() {
        let frame = CGRect(x: 100, y: 20, width: 300, height: 120)
        let grown = HUDPlacement().grow(frame, byHeight: 30, within: visible)
        XCTAssertEqual(grown.minY, 12)
        XCTAssertEqual(grown.height, 150)
        XCTAssertTrue(visible.contains(grown))
    }
}

final class OnboardingTests: XCTestCase {
    func testStatusesAndFinish() {
        var state = OnboardingState(screenRecordingGranted: false, appleIntelligenceAvailable: false, cloudConfigured: false)
        XCTAssertEqual(state.status(of: .screenAccess), .pending)
        XCTAssertEqual(state.status(of: .appleIntelligence), .unavailable)
        XCTAssertEqual(state.status(of: .cloud), .optional)
        XCTAssertFalse(state.canFinish)
        XCTAssertEqual(state.nextStep, .briefing)
        state.visitedSteps.insert(.briefing)
        XCTAssertEqual(state.nextStep, .screenAccess)
        state.screenRecordingGranted = true
        XCTAssertTrue(state.canFinish, "only screen access is required")
        XCTAssertEqual(OnboardingStep.cloud.code, "05")
    }
}

final class AccessibilityAnnouncementTests: XCTestCase {
    func testCollapsesLinesAndTruncates() throws {
        let parts = try XCTUnwrap(AccessibilityAnnouncement.parts(title: "Error\n kind", detail: String(repeating: "word ", count: 100), limit: 20))
        XCTAssertEqual(parts.title, "Error kind")
        XCTAssertLessThanOrEqual(parts.detail.count, 21)
        XCTAssertTrue(parts.detail.hasSuffix("…"))
    }

    func testEmptyIsNotAnnounced() {
        XCTAssertNil(AccessibilityAnnouncement.parts(title: " ", detail: "\n"))
    }
}
