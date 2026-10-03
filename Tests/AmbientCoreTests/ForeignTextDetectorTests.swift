import XCTest
@testable import AmbientCore

final class ForeignTextDetectorTests: XCTestCase {
    func makeDetector(guess: LanguageGuess?, familiar: Set<String> = []) -> ForeignTextDetector {
        ForeignTextDetector(
            identifier: StubLanguageIdentifier(fallback: guess),
            configuration: ForeignTextDetectorConfiguration(userLanguage: "ja", familiarLanguages: familiar)
        )
    }

    func testDetectsFrenchSentence() {
        let detector = makeDetector(guess: LanguageGuess(code: "fr", confidence: 0.95))
        let result = detector.evaluate("Je suis ici depuis ce matin.")
        XCTAssertEqual(result.foreignText?.language.code, "fr")
    }

    func testIgnoresShortWords() {
        let detector = makeDetector(guess: LanguageGuess(code: "en", confidence: 0.99))
        for text in ["OK", "Go", "AI", "Mac", "Cancel", "Bibliothèque"] {
            XCTAssertEqual(detector.evaluate(text), .ignored(.tooShort), text)
        }
    }

    func testIgnoresCommonUIPhrases() {
        let detector = makeDetector(guess: LanguageGuess(code: "en", confidence: 0.99))
        XCTAssertEqual(detector.evaluate("Accept all cookies"), .ignored(.commonPhrase))
        XCTAssertEqual(detector.evaluate("Remind me later"), .ignored(.commonPhrase))
    }

    func testIgnoresUserLanguage() {
        let detector = makeDetector(guess: LanguageGuess(code: "ja", confidence: 0.99))
        XCTAssertEqual(detector.evaluate("今日はとても良い天気ですね"), .ignored(.familiarLanguage))
    }

    func testIgnoresFamiliarLanguages() {
        let detector = makeDetector(guess: LanguageGuess(code: "en-US", confidence: 0.99), familiar: ["en"])
        XCTAssertEqual(detector.evaluate("The quick brown fox jumps over the lazy dog."), .ignored(.familiarLanguage))
    }

    func testIgnoresCodeAndURLs() {
        let detector = makeDetector(guess: LanguageGuess(code: "en", confidence: 0.99))
        XCTAssertEqual(detector.evaluate("Visit https://example.com/path/to/page today"), .ignored(.notProse))
        XCTAssertEqual(detector.evaluate("let value = items.map { $0.id }"), .ignored(.notProse))
        XCTAssertEqual(detector.evaluate("Total 2024-11-02 12345 67890 items"), .ignored(.notProse))
    }

    func testRequiresConfidence() {
        let low = makeDetector(guess: LanguageGuess(code: "de", confidence: 0.5))
        XCTAssertEqual(low.evaluate("Das ist ein ziemlich langer deutscher Satz."), .ignored(.lowConfidence))
        let shortText = makeDetector(guess: LanguageGuess(code: "de", confidence: 0.7))
        XCTAssertEqual(shortText.evaluate("Guten Morgen Welt"), .ignored(.lowConfidence), "short text needs 0.8")
        let unknown = makeDetector(guess: nil)
        XCTAssertEqual(unknown.evaluate("Ceci est une phrase en français."), .ignored(.unknownLanguage))
    }

    func testDetectsChineseWithoutSpaces() {
        let detector = makeDetector(guess: LanguageGuess(code: "zh-Hans", confidence: 0.9))
        XCTAssertNotNil(detector.evaluate("我们明天去北京吧。").foreignText)
        XCTAssertEqual(detector.evaluate("北京"), .ignored(.tooShort))
    }

    func testBaseLanguageCode() {
        XCTAssertEqual(LanguageCode.base("zh-Hans"), "zh")
        XCTAssertEqual(LanguageCode.base("en_US"), "en")
        XCTAssertEqual(LanguageCode.base("ja"), "ja")
    }
}
