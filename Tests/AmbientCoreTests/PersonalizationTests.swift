import XCTest
@testable import AmbientCore

final class PersonalizationTests: XCTestCase {
    let french = PersonalizationFeatures(action: .translate, language: "fr-FR", bundleIdentifier: "com.apple.Safari")
    let german = PersonalizationFeatures(action: .translate, language: "de", bundleIdentifier: "com.apple.Safari")

    func testFeedbackMovesScoreInExpectedDirection() {
        var model = PersonalizationModel()
        model.record(.openedDetails, for: french)
        XCTAssertGreaterThan(model.adjustment(for: french), 0)
        model.record(.markedNotUseful, for: french)
        XCTAssertLessThan(model.adjustment(for: french), 0)
    }

    func testWeightsFollowSpecRatio() {
        // close −1 / More +2 / search +3 (and an explicit "Not useful" −4)
        let features = PersonalizationFeatures(action: .translate, language: nil, bundleIdentifier: nil)
        func delta(_ feedback: PersonalizationFeedback) -> Double {
            var model = PersonalizationModel()
            model.record(feedback, for: features)
            return model.adjustment(for: features) / (PersonalizationFeedback.unit * 0.25)
        }
        XCTAssertEqual(delta(.dismissedQuickly), -1, accuracy: 0.0001)
        XCTAssertEqual(delta(.openedDetails), 2, accuracy: 0.0001)
        XCTAssertEqual(delta(.searched), 3, accuracy: 0.0001)
        XCTAssertEqual(delta(.markedNotUseful), -4, accuracy: 0.0001)
    }

    func testSearchedWeighsMoreThanOpened() {
        var opened = PersonalizationModel()
        opened.record(.openedDetails, for: french)
        var searched = PersonalizationModel()
        searched.record(.searched, for: french)
        XCTAssertGreaterThan(searched.adjustment(for: french), opened.adjustment(for: french))
    }

    func testLanguageSpecificFeedbackMostlyAffectsThatLanguage() {
        var model = PersonalizationModel()
        for _ in 0..<3 { model.record(.dismissedQuickly, for: french) }
        XCTAssertLessThan(model.adjustment(for: french), model.adjustment(for: german))
    }

    func testAdjustmentIsBounded() {
        var model = PersonalizationModel()
        for _ in 0..<100 { model.record(.searched, for: french) }
        XCTAssertLessThanOrEqual(model.adjustment(for: french), PersonalizationModel.maximumWeight)
        for _ in 0..<200 { model.record(.dismissedQuickly, for: french) }
        XCTAssertGreaterThanOrEqual(model.adjustment(for: french), -PersonalizationModel.maximumWeight)
    }

    func testModelRoundTripsThroughJSONWithoutContent() throws {
        var model = PersonalizationModel()
        model.record(.openedDetails, for: french)
        let data = try JSONEncoder().encode(model)
        XCTAssertEqual(try JSONDecoder().decode(PersonalizationModel.self, from: data), model)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("lang:fr"), "language is normalized to its base code")
    }

    func testStoreAdjustsRouterDecisions() {
        let store = PersonalizationStore()
        let sentence = "Nous sommes heureux de vous accueillir."
        let router = AIRouter(
            detector: ForeignTextDetector(identifier: StubLanguageIdentifier(fallback: LanguageGuess(code: "fr", confidence: 0.9)),
                                          configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")),
            adjuster: store
        )
        let ctx = context([textRegion(sentence)])
        let before = router.route(ctx)
        XCTAssertEqual(before.action, .translate)
        for _ in 0..<2 { store.record(.markedNotUseful, for: french) }
        XCTAssertLessThan(router.candidates(for: ctx).first?.importance ?? 1, before.importance)
        XCTAssertEqual(router.route(ctx), .ignore, "repeatedly rejected content stops being shown")
        store.reset()
        XCTAssertEqual(router.route(ctx).action, .translate)
    }

    func testStoreNotifiesChanges() {
        let expectation = expectation(description: "onChange")
        let store = PersonalizationStore(onChange: { model in
            XCTAssertFalse(model.weights.isEmpty)
            expectation.fulfill()
        })
        store.record(.openedDetails, for: french)
        wait(for: [expectation], timeout: 1)
    }
}
