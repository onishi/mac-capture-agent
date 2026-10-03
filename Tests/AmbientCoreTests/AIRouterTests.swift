import XCTest
@testable import AmbientCore

final class AIRouterTests: XCTestCase {
    func makeRouter(table: [String: LanguageGuess] = [:], fallback: LanguageGuess? = nil) -> AIRouter {
        AIRouter(detector: ForeignTextDetector(
            identifier: StubLanguageIdentifier(table: table, fallback: fallback),
            configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")
        ))
    }

    func testIgnoresByDefault() {
        let router = makeRouter()
        XCTAssertEqual(router.route(context([])), .ignore)
    }

    func testIgnoresUIChrome() {
        let router = makeRouter(fallback: LanguageGuess(code: "en", confidence: 0.99))
        let regions = ["OK", "Cancel", "Safari", "File", "Edit"].map { textRegion($0) }
        XCTAssertEqual(router.route(context(regions)).action, .ignore)
    }

    func testRoutesForeignSentenceToTranslate() {
        let sentence = "Le musée est fermé le lundi et les jours fériés."
        let router = makeRouter(table: [sentence: LanguageGuess(code: "fr", confidence: 0.97)],
                                fallback: LanguageGuess(code: "ja", confidence: 0.99))
        let action = router.route(context([textRegion("ファイル"), textRegion(sentence, y: 0.5)]))
        XCTAssertEqual(action.action, .translate)
        XCTAssertEqual(action.payload, sentence)
        XCTAssertEqual(action.sourceLanguage, "fr")
        XCTAssertEqual(action.region?.minY, 0.5)
        XCTAssertGreaterThanOrEqual(action.importance, InterestScore.showThreshold)
    }

    func testPicksMostImportantCandidate() {
        let short = "Bonjour à tous"
        let long = "Nous sommes heureux de vous accueillir dans notre nouvelle boutique."
        let router = makeRouter(fallback: LanguageGuess(code: "fr", confidence: 0.95))
        let action = router.route(context([textRegion(short), textRegion(long, y: 0.6)]))
        XCTAssertEqual(action.payload, long)
    }

    func testMenuBarTextIsIgnored() {
        let router = makeRouter(fallback: LanguageGuess(code: "fr", confidence: 0.9))
        let region = textRegion("Bonjour tout le monde", y: 0.005, height: 0.015)
        XCTAssertEqual(router.route(context([region])).action, .ignore)
    }

    func testVisualCategoriesStayBelowShowThresholdInMVP() {
        let router = makeRouter()
        let ctx = context([], categories: [.animal, .person, .plant, .landmark])
        XCTAssertEqual(router.route(ctx), .ignore)
        let candidates = router.candidates(for: ctx)
        XCTAssertEqual(Set(candidates.map(\.action)), [.identifyAnimal, .identifyPerson, .identifyPlant, .identifyLandmark])
        XCTAssertTrue(candidates.allSatisfy { $0.interestScore.level == .ignore })
    }

    func testPersonalizationCanSuppress() {
        struct Mute: InterestAdjusting {
            func adjust(_ score: InterestScore, action: SuggestedAction, context: AnalysisContext) -> InterestScore { InterestScore(0) }
        }
        let router = AIRouter(
            detector: ForeignTextDetector(identifier: StubLanguageIdentifier(fallback: LanguageGuess(code: "fr", confidence: 0.99)),
                                          configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")),
            adjuster: Mute()
        )
        XCTAssertEqual(router.route(context([textRegion("Nous sommes heureux de vous voir.")])), .ignore)
    }
}
