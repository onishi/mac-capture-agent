import XCTest
@testable import AmbientCore

final class TermExtractorTests: XCTestCase {
    let extractor = TermExtractor()

    func testFindsAcronymsAndKatakanaCompounds() {
        XCTAssertEqual(extractor.terms(in: "RAG で LLM の回答精度を上げるにはファインチューニングも検討"), ["RAG", "LLM", "ファインチューニング"])
        XCTAssertEqual(extractor.terms(in: "We compared CRDTs and OT for sync."), ["CRDTs", "OT"])
    }

    func testSkipsCommonWords() {
        XCTAssertEqual(extractor.terms(in: "Open the PDF via the API, then click OK. Download from the URL."), [])
        XCTAssertEqual(extractor.terms(in: "アカウントにログインしてパスワードを変更"), [])
        XCTAssertEqual(extractor.terms(in: "Chapter IV and XII"), [], "roman numerals")
        XCTAssertEqual(extractor.terms(in: "Version 2 of A1"), [], "too short / not enough letters")
        XCTAssertTrue(TermExtractor.isRomanNumeral("MCMXC"))
        XCTAssertFalse(TermExtractor.isRomanNumeral("LLM"))
    }

    func testCandidatesAreDedupedAndCarryContext() {
        let regions = [
            RecognizedTextRegion(text: "RAG improves grounding.", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.02), confidence: 0.9),
            RecognizedTextRegion(text: "Use RAG with a vector DB.", boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.02), confidence: 0.9)
        ]
        let candidates = extractor.candidates(in: regions)
        XCTAssertEqual(candidates.map(\.term), ["RAG", "DB"])
        XCTAssertEqual(candidates.first?.context, "RAG improves grounding.")
        XCTAssertEqual(candidates.first?.canonical, "rag")
    }

    func testEntityCanonicalization() {
        XCTAssertEqual(EntityName.canonical("  ＲＡＧ、 "), "rag")
        XCTAssertEqual(EntityName.canonical("Cate   Blanchett"), "cate blanchett")
        XCTAssertEqual(ExtractedEntity(type: .person, name: "Cate Blanchett").canonicalName, "cate blanchett")
    }
}

final class TermRoutingTests: XCTestCase {
    func router(language: LanguageGuess) -> AIRouter {
        AIRouter(detector: ForeignTextDetector(identifier: StubLanguageIdentifier(fallback: language),
                                               configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")))
    }

    func testTermsLandInOptionalBandAndAreNeverShownByRules() {
        let r = router(language: LanguageGuess(code: "ja", confidence: 0.99))
        let ctx = context([textRegion("RAG を使った検索システムの構築について")])
        let decision = r.decide(ctx)
        XCTAssertEqual(decision.selected, .ignore)
        let term = decision.candidates.first { $0.action == .explainTerm }
        XCTAssertEqual(term?.payload, "RAG")
        XCTAssertEqual(term?.interestScore.level, .optional)
        XCTAssertEqual(term?.context, "RAG を使った検索システムの構築について")
    }

    func testEscalationPicksOptionalCandidatesOnlyWhenNothingIsShown() {
        let r = router(language: LanguageGuess(code: "ja", confidence: 0.99))
        let decision = r.decide(context([textRegion("RAG を使った検索システムの構築について")]))
        let escalated = RouterEscalation.candidates(in: decision)
        XCTAssertEqual(escalated.map(\.action), [.explainTerm])
        let accepted = RouterEscalation.apply(show: true, to: escalated[0])
        XCTAssertEqual(accepted.interestScore.level, .show)
        XCTAssertEqual(accepted.context, escalated[0].context)
        XCTAssertEqual(RouterEscalation.apply(show: false, to: escalated[0]), .ignore)

        let french = router(language: LanguageGuess(code: "fr", confidence: 0.97))
        let shown = french.decide(context([textRegion("Nous utilisons RAG pour améliorer les réponses du modèle.")]))
        XCTAssertEqual(shown.selected.action, .translate)
        XCTAssertTrue(RouterEscalation.candidates(in: shown).isEmpty, "something is already shown")
    }

    func testRateLimiter() {
        var limiter = RateLimiter(minimumInterval: 10)
        XCTAssertTrue(limiter.allow(now: 0))
        XCTAssertFalse(limiter.allow(now: 5))
        XCTAssertTrue(limiter.allow(now: 10))
    }
}

final class ReappearanceTests: XCTestCase {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testDays() {
        XCTAssertNil(Reappearance.daysSince(nil, now: date(5, 10), calendar: calendar))
        XCTAssertNil(Reappearance.daysSince(date(5, 8), now: date(5, 10), calendar: calendar), "same day")
        XCTAssertEqual(Reappearance.daysSince(date(4, 23), now: date(5, 1), calendar: calendar), 1)
        XCTAssertEqual(Reappearance.daysSince(date(2, 10), now: date(5, 10), calendar: calendar), 3)
    }

    func testLabels() {
        XCTAssertEqual(Reappearance.label(days: 3, language: "ja"), "3日前にも表示されています")
        XCTAssertEqual(Reappearance.label(days: 1, language: "ja-JP"), "昨日も表示されています")
        XCTAssertEqual(Reappearance.label(days: 3, language: "en"), "Seen 3 days ago")
    }

    func testMessageCopyKeepsEverything() {
        let message = HUDMessage(kind: .explanation, title: "RAG", original: "Retrieval-Augmented Generation", detail: "…", anchor: nil)
        let seen = date(2, 10)
        let copy = message.withPreviouslySeen(seen)
        XCTAssertEqual(copy.id, message.id)
        XCTAssertEqual(copy.kind, .explanation)
        XCTAssertEqual(copy.previouslySeen, seen)
    }
}
