import XCTest
@testable import AmbientCore

final class ArchiveQuestionTests: XCTestCase {
    func testDetectsQuestions() {
        XCTAssertTrue(ArchiveQuestion.isQuestion("昨日読んだ RAG の記事は？"))
        XCTAssertTrue(ArchiveQuestion.isQuestion("what was the French notice?"))
        XCTAssertTrue(ArchiveQuestion.isQuestion("? museum opening hours"))
        XCTAssertFalse(ArchiveQuestion.isQuestion("昨日のフランス語"), "plain search")
        XCTAssertFalse(ArchiveQuestion.isQuestion("??"))
        XCTAssertEqual(ArchiveQuestion.question(from: "？ 美術館の開館時間"), "美術館の開館時間")
    }

    func testPromptNumbersAndClipsEvidence() {
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let evidence = (0..<10).map { index in
            ArchiveEvidence(date: Date(timeIntervalSince1970: 1_791_374_400 + Double(index) * 60), application: index == 0 ? nil : "Safari",
                            text: index == 0 ? String(repeating: "a", count: 500) : "Musée ouvert\n9h–18h → 美術館 9時〜18時")
        }
        let prompt = ArchiveQuestion.prompt(question: "開館時間は？", evidence: evidence, now: Date(timeIntervalSince1970: 1_791_374_400), timeZone: utc)
        XCTAssertTrue(prompt.contains("Question: 開館時間は？"))
        XCTAssertTrue(prompt.contains("[1] 2026-10-07 12:00 -: "))
        XCTAssertTrue(prompt.contains("[8] "))
        XCTAssertFalse(prompt.contains("[9] "), "at most \(ArchiveQuestion.maximumEvidence) records")
        XCTAssertFalse(prompt.contains(String(repeating: "a", count: ArchiveQuestion.maximumEvidenceLength + 1)))
        XCTAssertTrue(ArchiveQuestion.instructions(targetLanguage: "ja").contains(ArchiveQuestion.notFoundMarker))
    }

    func testEvidenceFromEntry() {
        let entry = VisualMemoryEntry(timestamp: Date(), kind: .translation, application: "Safari", bundleIdentifier: nil,
                                      windowTitle: nil, url: nil, sourceLanguage: "fr", targetLanguage: "ja",
                                      original: "Bonjour", translation: "こんにちは", features: nil)
        XCTAssertEqual(ArchiveEvidence(entry).text, "Bonjour → こんにちは")
    }

    func testSanitizeAndCitations() {
        XCTAssertNil(ArchiveQuestion.sanitize("NOT_FOUND"))
        XCTAssertNil(ArchiveQuestion.sanitize("  "))
        XCTAssertEqual(ArchiveQuestion.sanitize("「9時〜18時です [1]」"), "9時〜18時です [1]")
        XCTAssertEqual(ArchiveQuestion.citations(in: "9時から [2][1]、月曜休館 [2] [9]", evidenceCount: 3), [2, 1])
        XCTAssertTrue(ArchiveQuestion.citations(in: "no cite", evidenceCount: 3).isEmpty)
    }
}

final class IntelSourceTests: XCTestCase {
    func message(_ kind: HUDMessage.Kind, source: IntelSource? = nil) -> HUDMessage {
        HUDMessage(kind: kind, title: "t", original: "o", detail: "d", anchor: nil, source: source)
    }

    func testDefaultsByKindAndOverrides() {
        XCTAssertEqual(message(.translation).source, .onDeviceML)
        XCTAssertEqual(message(.identification).source, .onDeviceLLM)
        XCTAssertEqual(message(.conversion).source, .rule)
        XCTAssertEqual(message(.resume).source, .history)
        XCTAssertNil(message(.noIntel).source)
        XCTAssertEqual(message(.errorAnalysis, source: .rule).source, .rule, "rule-based error hint")
        XCTAssertEqual(message(.explanation, source: .rule).withPreviouslySeen(Date()).source, .rule, "kept on copy")
        XCTAssertTrue(IntelSource.onDeviceLLM.label.contains("ESTIMATE"))
    }
}
