import XCTest
@testable import AmbientCore

final class PersonalizationTests: XCTestCase {
    let french = PersonalizationFeatures(action: .translate, language: "fr-FR", bundleIdentifier: "com.apple.Safari")
    let german = PersonalizationFeatures(action: .translate, language: "de", bundleIdentifier: "com.apple.Safari")

    func testFeedbackMovesScoreInExpectedDirection() {
        var model = PersonalizationModel()
        model.record(.openedDetails, for: french)
        XCTAssertGreaterThan(model.adjustment(for: french), 0)
        model.record(.dismissedQuickly, for: french)
        model.record(.dismissedQuickly, for: french)
        XCTAssertLessThan(model.adjustment(for: french), 0)
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
        for _ in 0..<4 { store.record(.dismissedQuickly, for: french) }
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
