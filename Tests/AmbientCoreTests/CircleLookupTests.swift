import XCTest
@testable import AmbientCore

final class CircleGestureTests: XCTestCase {
    let screen = CGSize(width: 1000, height: 800)

    /// A stroke around (cx, cy) from 0° to `degrees`, evenly over `duration` seconds.
    func arc(cx: Double = 500, cy: Double = 400, rx: Double = 100, ry: Double = 100,
             degrees: Double = 370, count: Int = 40, duration: TimeInterval = 0.8, start: TimeInterval = 0) -> [PointerSample] {
        (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            let angle = fraction * degrees * .pi / 180
            return PointerSample(x: cx + rx * cos(angle), y: cy + ry * sin(angle), time: start + fraction * duration)
        }
    }

    func testRecognizesACircleAndReturnsThePaddedArea() throws {
        let rect = try XCTUnwrap(CircleGestureRecognizer().recognize(arc(), screenSize: screen))
        XCTAssertEqual(rect.minX, 0.38, accuracy: 0.01)
        XCTAssertEqual(rect.width, 0.24, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 0.35, accuracy: 0.01)
        XCTAssertEqual(rect.height, 0.30, accuracy: 0.01)
    }

    func testAcceptsEllipsesAndCounterClockwise() {
        XCTAssertNotNil(CircleGestureRecognizer().recognize(arc(rx: 160, ry: 80), screenSize: screen))
        XCTAssertNotNil(CircleGestureRecognizer().recognize(arc(degrees: -360), screenSize: screen))
    }

    func testRejectsOrdinaryPointerMovement() {
        let recognizer = CircleGestureRecognizer()
        let line = (0..<30).map { PointerSample(x: 100 + Double($0) * 20, y: 100, time: Double($0) * 0.03) }
        XCTAssertNil(recognizer.recognize(line, screenSize: screen), "straight line")
        XCTAssertNil(recognizer.recognize(arc(degrees: 180), screenSize: screen), "half circle is not closed")
        XCTAssertNil(recognizer.recognize(arc(rx: 5, ry: 5), screenSize: screen), "too small")
        XCTAssertNil(recognizer.recognize(arc(duration: 6), screenSize: screen), "too slow")
        XCTAssertNil(recognizer.recognize(arc(degrees: 1080, count: 120, duration: 2), screenSize: screen), "three loops is scribbling")
        XCTAssertNil(recognizer.recognize(arc(rx: 200, ry: 30), screenSize: screen), "too flat")
        let zigzag = (0..<30).map { PointerSample(x: 300 + Double($0 % 2) * 120, y: 300 + Double($0) * 4, time: Double($0) * 0.03) }
        XCTAssertNil(recognizer.recognize(zigzag, screenSize: screen), "zigzag")
    }

    func testTotalTurningIgnoresJitter() {
        let turning = CircleGestureRecognizer.totalTurning(arc(degrees: 360, count: 73), minimumStep: 2)
        XCTAssertEqual(abs(turning) * 180 / .pi, 355, accuracy: 10)
    }

    func testTrackerRecognizesOnReleaseAndResets() {
        var tracker = CircleGestureTracker()
        for sample in arc() {
            XCTAssertNil(tracker.update(position: CGPoint(x: sample.x, y: sample.y), time: sample.time, active: true, screenSize: screen))
        }
        XCTAssertTrue(tracker.isTracking)
        XCTAssertNotNil(tracker.update(position: .zero, time: 0.9, active: false, screenSize: screen))
        XCTAssertFalse(tracker.isTracking)
        XCTAssertNil(tracker.update(position: .zero, time: 1.0, active: false, screenSize: screen), "nothing to recognize")
    }

    func testRestingBeforeDrawingDoesNotCount() {
        var tracker = CircleGestureTracker()
        _ = tracker.update(position: CGPoint(x: 600, y: 400), time: 0, active: true, screenSize: screen)
        for sample in arc(start: 2) {
            _ = tracker.update(position: CGPoint(x: sample.x, y: sample.y), time: sample.time, active: true, screenSize: screen)
        }
        XCTAssertNotNil(tracker.update(position: .zero, time: 3, active: false, screenSize: screen))
    }

    func testCancelDropsTheStroke() {
        var tracker = CircleGestureTracker()
        for sample in arc() {
            _ = tracker.update(position: CGPoint(x: sample.x, y: sample.y), time: sample.time, active: true, screenSize: screen)
        }
        tracker.cancel()
        XCTAssertNil(tracker.update(position: .zero, time: 1, active: false, screenSize: screen))
    }
}

final class ActiveLookupPlannerTests: XCTestCase {
    func candidate(_ action: SuggestedAction, _ payload: String) -> RoutedAction {
        RoutedAction(action: action, confidence: 0.5, importance: 0.1, region: nil, payload: payload)
    }

    func plan(qr: [String] = [], _ candidates: [RoutedAction] = [], text: String = "", conversions: [UnitConversion] = [],
              categories: [VisualCategory] = [], llm: Bool = true) -> ActiveLookupPlan {
        ActiveLookupPlanner.plan(qrPayloads: qr, candidates: candidates, text: text, conversions: conversions,
                                 categories: categories, canUseLanguageModel: llm)
    }

    func testOrder() {
        let error = candidate(.explainError, "TypeError: x is not a function")
        let foreign = candidate(.translate, "Je ne regrette rien")
        XCTAssertEqual(plan(qr: ["https://example.com"], [error]), .qrCode("https://example.com"))
        XCTAssertEqual(plan([foreign, error], text: "…"), .explainError(error))
        XCTAssertEqual(plan([foreign], text: "Je ne regrette rien"), .translate(foreign))
    }

    func testIgnoresScoresBecauseTheUserAsked() {
        let lowScore = candidate(.translate, "Guten Morgen zusammen")
        XCTAssertEqual(lowScore.interestScore.level, .ignore)
        XCTAssertEqual(plan([lowScore], text: "Guten Morgen zusammen"), .translate(lowScore))
    }

    func testShortQuantityIsAboutUnits() {
        let conversion = UnitConversion(original: "72°F", converted: "22.2 °C")
        let foreign = candidate(.translate, "High 72°F today")
        XCTAssertEqual(plan([foreign], text: "High 72°F today", conversions: [conversion]), .convertUnits([conversion]))
    }

    func testTermCodePictureAndDescription() {
        let term = candidate(.explainTerm, "RAG")
        XCTAssertEqual(plan([term], text: "RAG"), .explainTerm(term))
        let code = "func load() { let data = try fetch(); return decode(data) }"
        XCTAssertEqual(plan(text: code), .explainCode(code))
        XCTAssertEqual(plan(text: "", categories: [.person, .animal]), .identify(.animal))
        let prose = String(repeating: "This paragraph describes the quarterly results. ", count: 3)
        XCTAssertEqual(plan([term], text: prose), .describe(prose.trimmingCharacters(in: .whitespaces)))
    }

    func testWithoutTheModel() {
        let term = candidate(.explainTerm, "RAG")
        let prose = String(repeating: "This paragraph mentions RAG in passing. ", count: 3)
        XCTAssertEqual(plan([term], text: prose, llm: false), .explainTerm(term), "the glossary may know it")
        XCTAssertEqual(plan(text: prose, llm: false), .nothing)
        XCTAssertEqual(plan(text: "func a() { return b() } let x = y", llm: false), .nothing)
    }

    func testDescriptionSanitizer() {
        XCTAssertEqual(RegionDescription.sanitize("「売上の表です」", input: "Q3 revenue 120"), "売上の表です")
        XCTAssertNil(RegionDescription.sanitize("  ", input: "x"))
        XCTAssertNil(RegionDescription.sanitize("Q3 revenue 120", input: "Q3 revenue 120"), "just repeats")
        XCTAssertEqual(RegionDescription.sanitize(String(repeating: "あ", count: 300), input: "x")?.count, RegionDescription.maximumLength)
        XCTAssertTrue(RegionDescription.instructions(targetLanguage: "ja").contains("\"ja\""))
    }
}
