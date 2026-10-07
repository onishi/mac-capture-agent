import XCTest
import AmbientCore
@testable import AmbientStore

private struct NoEmbedding: TextEmbedding {
    func vector(for text: String, language: String) -> [Float]? { nil }
}

final class AIAnswerStoreTests: XCTestCase {
    func makeStore(retentionDays: Int = 7) -> IntelStore {
        IntelStore(url: nil, retentionDays: retentionDays, userLanguage: "ja", embedding: NoEmbedding())
    }

    func testRecordsNewestFirstAndFilters() async {
        let store = makeStore()
        await store.recordAIAnswer(AIAnswerRecord(date: Date().addingTimeInterval(-60), feature: .termExplanation,
                                                  subject: "RAG", answer: "検索した情報で回答する手法", outcome: .shown,
                                                  durationMilliseconds: 840, application: "Safari"))
        await store.recordAIAnswer(AIAnswerRecord(feature: .publicFigure, subject: "John Smith", answer: "not a public figure",
                                                  outcome: .declined))
        let all = await store.aiAnswers()
        XCTAssertEqual(all.map(\.subject), ["John Smith", "RAG"])
        XCTAssertEqual(all.last?.durationMilliseconds, 840)
        XCTAssertEqual(all.last?.application, "Safari")
        XCTAssertEqual(all.first?.outcome, .declined)

        let filtered = await store.aiAnswers(matching: "検索")
        XCTAssertEqual(filtered.map(\.subject), ["RAG"])
        let byFeature = await store.aiAnswers(matching: "publicFigure")
        XCTAssertEqual(byFeature.count, 1)
        let literal = await store.aiAnswers(matching: "%")
        XCTAssertTrue(literal.isEmpty, "LIKE wildcards are escaped")
    }

    func testRetentionAndPurge() async {
        let store = makeStore(retentionDays: 1)
        await store.recordAIAnswer(AIAnswerRecord(date: Date().addingTimeInterval(-3 * 86400), feature: .briefing,
                                                  subject: "old", answer: "a", outcome: .shown))
        await store.recordAIAnswer(AIAnswerRecord(feature: .briefing, subject: "new", answer: "b", outcome: .shown))
        await store.configure(retentionDays: 1, userLanguage: "ja")   // prunes
        let remaining = await store.aiAnswers()
        XCTAssertEqual(remaining.map(\.subject), ["new"])
        await store.removeAll()
        let afterPurge = await store.aiAnswers()
        XCTAssertTrue(afterPurge.isEmpty)
    }
}
