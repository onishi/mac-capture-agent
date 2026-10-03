import XCTest
@testable import AmbientCore

final class DecodeEffectTests: XCTestCase {
    func testEndpoints() {
        let text = "Je suis ici."
        XCTAssertEqual(DecodeEffect.frame(of: text, progress: 1, tick: 3), text)
        let scrambled = DecodeEffect.frame(of: text, progress: 0, tick: 3)
        XCTAssertEqual(scrambled.count, text.count, "keeps length so layout doesn't jump")
        XCTAssertNotEqual(scrambled, text)
    }

    func testRevealsPrefixAndKeepsSpacesAndPunctuation() {
        let text = "Bonjour le monde."
        let frame = Array(DecodeEffect.frame(of: text, progress: 0.5, tick: 7))
        let original = Array(text)
        XCTAssertEqual(String(frame.prefix(8)), String(original.prefix(8)))
        for (i, c) in original.enumerated() where c == " " || c == "." {
            XCTAssertEqual(frame[i], c)
        }
    }

    func testCJKUsesKatakanaGlyphs() {
        let frame = DecodeEffect.frame(of: "私はここにいます", progress: 0, tick: 1)
        XCTAssertTrue(frame.allSatisfy { DecodeEffect.cjkGlyphs.contains($0) })
    }

    func testTickChangesGlyphs() {
        let a = DecodeEffect.frame(of: "ABCDEFGHIJ", progress: 0, tick: 1)
        let b = DecodeEffect.frame(of: "ABCDEFGHIJ", progress: 0, tick: 2)
        XCTAssertNotEqual(a, b)
    }

    func testProgressEasing() {
        XCTAssertEqual(DecodeEffect.progress(elapsed: 0, duration: 1), 0)
        XCTAssertEqual(DecodeEffect.progress(elapsed: 2, duration: 1), 1)
        XCTAssertGreaterThan(DecodeEffect.progress(elapsed: 0.5, duration: 1), 0.5, "ease-out")
        XCTAssertEqual(DecodeEffect.progress(elapsed: 0.1, duration: 0), 1)
    }

    func testCodenames() {
        let id = UUID(uuidString: "3F2A0000-0000-0000-0000-000000000000")!
        XCTAssertEqual(HUDCodename.targetCode(for: id), "TGT-3F2A")
        XCTAssertEqual(HUDCodename.route(source: "fr-FR", target: "ja"), "FR ▸ JA")
        XCTAssertEqual(HUDCodename.route(source: nil, target: "ja"), "?? ▸ JA")
        XCTAssertEqual(HUDCodename.meterSegments(confidence: 0.73), 7)
        XCTAssertEqual(HUDCodename.meterSegments(confidence: 2), 10)
    }

    func testBriefingDurationExtension() {
        let message = HUDMessage(kind: .translation, title: "French", original: "Je suis ici.", detail: "私はここにいます。", anchor: nil, confidence: 1.5)
        XCTAssertEqual(message.confidence, 1)
        XCTAssertGreaterThan(message.displayDuration(withBriefing: true), message.displayDuration(withBriefing: false))
        XCTAssertLessThanOrEqual(message.displayDuration(withBriefing: true), 8)
    }
}

final class BriefingTests: XCTestCase {
    let request = BriefingRequest(original: "Le musée est fermé le lundi.", translation: "美術館は月曜日休館です。",
                                  sourceLanguage: "fr", targetLanguage: "ja", appName: "Safari")

    func testPromptContainsContextAndIsBounded() {
        let prompt = BriefingPrompt.prompt(for: request)
        XCTAssertTrue(prompt.contains("Le musée"))
        XCTAssertTrue(prompt.contains("Safari"))
        let long = BriefingRequest(original: String(repeating: "a", count: 5_000), translation: "b",
                                   sourceLanguage: nil, targetLanguage: "ja", appName: nil)
        XCTAssertLessThan(BriefingPrompt.prompt(for: long).count, 1_200)
        XCTAssertTrue(BriefingPrompt.instructions(targetLanguage: "ja").contains("\"ja\""))
    }

    func testSanitizerCleansOutput() {
        XCTAssertEqual(BriefingSanitizer.sanitize("「観光前に営業日を確認」\n余計な行", translation: request.translation), "観光前に営業日を確認")
        XCTAssertEqual(BriefingSanitizer.sanitize("Note: Check opening days", translation: request.translation), "Check opening days")
    }

    func testSanitizerRejectsUselessOutput() {
        XCTAssertNil(BriefingSanitizer.sanitize("-", translation: request.translation))
        XCTAssertNil(BriefingSanitizer.sanitize("   ", translation: request.translation))
        XCTAssertNil(BriefingSanitizer.sanitize("美術館は月曜日休館です。", translation: request.translation), "repeating the translation is useless")
    }

    func testSanitizerTruncates() {
        let text = BriefingSanitizer.sanitize(String(repeating: "あ", count: 200), translation: "x")
        XCTAssertEqual(text?.count, BriefingSanitizer.maximumLength)
        XCTAssertEqual(text?.last, "…")
    }
}
