import XCTest
@testable import AmbientCore

final class InterestScoreTests: XCTestCase {
    func testClampingAndLevels() {
        XCTAssertEqual(InterestScore(-1).value, 0)
        XCTAssertEqual(InterestScore(2).value, 1)
        XCTAssertEqual(InterestScore(.nan).value, 0)
        XCTAssertEqual(InterestScore(0.49).level, .ignore)
        XCTAssertEqual(InterestScore(0.5).level, .optional)
        XCTAssertEqual(InterestScore(0.69).level, .optional)
        XCTAssertEqual(InterestScore(0.7).level, .show)
        XCTAssertEqual(InterestScore(1).level, .show)
    }

    func foreign(_ text: String, confidence: Double = 0.95) -> ForeignText {
        ForeignText(text: text, language: LanguageGuess(code: "fr", confidence: confidence), heuristics: TextHeuristics(text))
    }

    func testSentenceScoresHigherThanFragment() {
        let scorer = InterestScorer()
        let ctx = context([])
        let sentence = "Je voudrais réserver une table pour deux personnes."
        let fragment = "Voir aussi"
        let a = scorer.scoreTranslation(foreign(sentence), region: textRegion(sentence), context: ctx)
        let b = scorer.scoreTranslation(foreign(fragment), region: textRegion(fragment), context: ctx)
        XCTAssertGreaterThan(a, b)
        XCTAssertEqual(a.level, .show)
    }

    func testLowOCRConfidenceReducesScore() {
        let scorer = InterestScorer()
        let text = "Je voudrais réserver une table pour deux personnes."
        let good = scorer.scoreTranslation(foreign(text), region: textRegion(text, confidence: 0.9), context: context([]))
        let bad = scorer.scoreTranslation(foreign(text), region: textRegion(text, confidence: 0.3), context: context([]))
        XCTAssertGreaterThan(good, bad)
    }

    func testCodingAppsArePenalized() {
        let scorer = InterestScorer()
        let text = "Je voudrais réserver une table pour deux personnes."
        let browser = scorer.scoreTranslation(foreign(text), region: textRegion(text), context: context([]))
        let editor = scorer.scoreTranslation(foreign(text), region: textRegion(text), context: context([], bundle: "com.microsoft.VSCode"))
        XCTAssertGreaterThan(browser, editor)
    }
}
