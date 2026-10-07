import XCTest
@testable import AmbientCore

final class LocalIdentificationTests: XCTestCase {
    func answer(_ category: String, _ name: String, scientific: String = "", confidence: Double) -> IdentificationAnswer {
        IdentificationAnswer(category: category, name: name, scientificName: scientific, facts: [], confidence: confidence)
    }

    func testAcceptsOnlyConfidentMatchingCategory() {
        XCTAssertTrue(IdentificationPolicy.accept(answer("animal", "カワセミ", confidence: 0.9), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("animal", "カワセミ", confidence: 0.4), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("none", "", confidence: 0.9), hint: .animal))
        XCTAssertFalse(IdentificationPolicy.accept(answer("plant", "バラ", confidence: 0.9), hint: .animal), "category mismatch")
    }

    func testHedging() {
        XCTAssertEqual(IdentificationPolicy.displayName("カワセミ", confidence: 0.9, language: "ja"), "カワセミ")
        XCTAssertEqual(IdentificationPolicy.displayName("カワセミ", confidence: 0.6, language: "ja"), "カワセミ（かもしれません）")
        XCTAssertEqual(IdentificationPolicy.displayName("Kingfisher", confidence: 0.6, language: "en"), "Kingfisher (possibly)")
    }

    func testLocalConfidenceIsNeverAssertiveWithoutScreenText() {
        let sure = answer("animal", "カワセミ", scientific: "Alcedo atthis", confidence: 0.95)
        let uncorroborated = IdentificationPolicy.localConfidence(sure, labelConfidence: 0.9, nearbyText: "川辺で撮影")
        XCTAssertLessThan(uncorroborated, IdentificationPolicy.assertiveConfidence, "model self-confidence is not trusted")
        XCTAssertGreaterThanOrEqual(uncorroborated, IdentificationPolicy.minimumConfidence)
        XCTAssertEqual(IdentificationPolicy.localConfidence(sure, labelConfidence: 0.4, nearbyText: ""), 0.4, "capped by the classifier")
        let captioned = IdentificationPolicy.localConfidence(sure, labelConfidence: 0.4, nearbyText: "今朝のカワセミ（野川）")
        XCTAssertGreaterThanOrEqual(captioned, IdentificationPolicy.assertiveConfidence, "the caption names it")
        XCTAssertTrue(IdentificationPolicy.isCorroborated(sure, by: "Photo: Alcedo atthis"))
        XCTAssertFalse(IdentificationPolicy.isCorroborated(answer("animal", "鳥", confidence: 0.9), by: "鳥"), "one-letter names prove nothing")
    }

    func testPublicFigureMustMatchNameOnScreen() {
        let cate = PublicFigureAnswer(isPublicFigure: true, name: "Cate Blanchett", role: "Actor", knownFor: ["TÁR"], confidence: 0.95)
        XCTAssertTrue(IdentificationPolicy.accept(cate, nameOnScreen: "Cate Blanchett"))
        XCTAssertTrue(IdentificationPolicy.accept(cate, nameOnScreen: "Blanchett"))
        XCTAssertFalse(IdentificationPolicy.accept(cate, nameOnScreen: "John Smith"), "answer about someone else")
        var private_ = cate
        private_.isPublicFigure = false
        XCTAssertFalse(IdentificationPolicy.accept(private_, nameOnScreen: "Cate Blanchett"))
        var unsure = cate
        unsure.confidence = 0.6
        XCTAssertFalse(IdentificationPolicy.accept(unsure, nameOnScreen: "Cate Blanchett"))
    }

    func testInstructionsAreTextOnlyAndForbidPeople() {
        let instructions = IdentificationAnswer.instructions(targetLanguage: "ja")
        XCTAssertTrue(instructions.contains("Never identify or describe people"))
        XCTAssertTrue(instructions.contains("You cannot see the image"))
        XCTAssertTrue(PublicFigureAnswer.instructions(targetLanguage: "ja").contains("Never guess"))
        let prompt = IdentificationAnswer.prompt(labels: [VisualLabel(identifier: "kingfisher", confidence: 0.71)], hint: .animal, context: "caption")
        XCTAssertTrue(prompt.contains("kingfisher (0.71)"))
        XCTAssertTrue(prompt.contains("Nearby text: caption"))
    }

    func testBrowserURLs() {
        XCTAssertEqual(IdentificationPolicy.webSearchURL(for: "Alcedo atthis")?.absoluteString, "https://www.google.com/search?q=Alcedo%20atthis")
        XCTAssertEqual(IdentificationPolicy.wikipediaURL(for: "カワセミ", language: "ja")?.host, "ja.wikipedia.org")
        XCTAssertEqual(IdentificationPolicy.wikipediaURL(for: "x", language: "zh-Hans")?.host, "zh.wikipedia.org")
    }
}

final class VisualLabelSelectorTests: XCTestCase {
    func testKeepsSpecificLabelsOfTheHintedCategory() {
        let labels = [
            VisualLabel(identifier: "animal", confidence: 0.95),
            VisualLabel(identifier: "bird", confidence: 0.9),
            VisualLabel(identifier: "kingfisher", confidence: 0.62),
            VisualLabel(identifier: "outdoor", confidence: 0.8),
            VisualLabel(identifier: "water", confidence: 0.5),
            VisualLabel(identifier: "heron", confidence: 0.1)
        ]
        let selected = VisualLabelSelector.select(labels, for: .animal)
        XCTAssertEqual(selected.map(\.identifier), ["kingfisher"], "generic and low-confidence labels are dropped")
        XCTAssertEqual(VisualLabelSelector.topConfidence(selected), 0.62)
    }

    func testFallsBackToOneGenericLabel() {
        let labels = [VisualLabel(identifier: "bird", confidence: 0.9), VisualLabel(identifier: "animal", confidence: 0.95)]
        XCTAssertEqual(VisualLabelSelector.select(labels, for: .animal).map(\.identifier), ["animal"])
        XCTAssertTrue(VisualLabelSelector.select([], for: .plant).isEmpty)
    }

    func testReadableLabel() {
        XCTAssertEqual(VisualLabel(identifier: "golden_retriever", confidence: 1).readable, "golden retriever")
    }
}

final class AcronymGlossaryTests: XCTestCase {
    func testExtractsDefinitionsInBothOrders() {
        let found = AcronymGlossary.definitions(in: "We use Retrieval-Augmented Generation (RAG) with a large language model (LLM).")
        XCTAssertEqual(found, [
            AcronymDefinition(acronym: "RAG", expansion: "Retrieval-Augmented Generation"),
            AcronymDefinition(acronym: "LLM", expansion: "large language model")
        ])
        XCTAssertEqual(AcronymGlossary.definitions(in: "the CRDT (Conflict-free Replicated Data Type) approach"),
                       [AcronymDefinition(acronym: "CRDT", expansion: "Conflict-free Replicated Data Type")])
    }

    func testHandlesStopWordsMultiLetterPrefixesAndPlurals() {
        XCTAssertEqual(AcronymGlossary.definitions(in: "the Department of Energy (DOE) said").first?.expansion, "Department of Energy")
        XCTAssertEqual(AcronymGlossary.definitions(in: "served over HTTP Secure (HTTPS) only").first?.expansion, "HTTP Secure")
        XCTAssertEqual(AcronymGlossary.definitions(in: "Application Programming Interfaces (APIs) are").first,
                       AcronymDefinition(acronym: "API", expansion: "Application Programming Interfaces"))
    }

    func testRejectsNonDefinitions() {
        XCTAssertTrue(AcronymGlossary.definitions(in: "Call me tomorrow (USA time)").isEmpty)
        XCTAssertTrue(AcronymGlossary.definitions(in: "a quick test (QA)").isEmpty, "letters don't match")
        XCTAssertTrue(AcronymGlossary.definitions(in: "Swift (Apple)").isEmpty, "not an acronym")
    }

    func testLearnsLooksUpAndEvicts() {
        var glossary = AcronymGlossary(capacity: 2)
        XCTAssertEqual(glossary.learn(from: "Retrieval-Augmented Generation (RAG)").count, 1)
        XCTAssertEqual(glossary.lookup("rag")?.expansion, "Retrieval-Augmented Generation")
        XCTAssertTrue(glossary.learn(from: "Retrieval-Augmented Generation (RAG)").isEmpty, "already known")
        glossary.learn(from: "large language model (LLM) and Key Performance Indicator (KPI)")
        XCTAssertEqual(glossary.count, 2)
        XCTAssertNil(glossary.lookup("RAG"), "oldest evicted")
        glossary.removeAll()
        XCTAssertEqual(glossary.count, 0)
    }
}

final class UnitConverterTests: XCTestCase {
    func convert(_ text: String, _ language: String = "ja") -> [String] {
        UnitConverter.conversions(in: text, targetLanguage: language).map { "\($0.original) → \($0.converted)" }
    }

    func testCommonUnits() {
        XCTAssertEqual(convert("It's 72°F outside"), ["72°F → 22.2 °C"])
        XCTAssertEqual(convert("a 5 mile run"), ["5 mile → 8.05 km"])
        XCTAssertEqual(convert("He is 6 ft tall and weighs 180 lbs"), ["6 ft → 1.83 m", "180 lbs → 81.6 kg"])
        XCTAssertEqual(convert("12 oz of coffee"), ["12 oz → 340 g"])
        XCTAssertEqual(convert("speed limit 65 mph"), ["65 mph → 105 km/h"])
        XCTAssertEqual(convert("1,200 sq ft apartment"), ["1,200 sq ft → 111 m²"])
        XCTAssertEqual(convert("a 2 inch screw"), ["2 inch → 5.08 cm"])
    }

    func testLongerUnitWinsAndOrderIsReadingOrder() {
        XCTAssertEqual(convert("drove 30 miles at 60 mph"), ["30 miles → 48.3 km", "60 mph → 96.6 km/h"])
    }

    func testIgnoresNonQuantitiesAndEnglishReaders() {
        XCTAssertTrue(convert("version 2.5 is out").isEmpty)
        XCTAssertTrue(convert("in 2026 we will").isEmpty, "bare 'in' is a preposition")
        XCTAssertTrue(convert("It's 72°F", "en").isEmpty)
        XCTAssertEqual(UnitConverter.conversions(in: "1 mi 2 mi 3 mi 4 mi", targetLanguage: "ja", limit: 2).count, 2)
    }

    func testFormatting() {
        XCTAssertEqual(UnitConverter.format(22.2222), "22.2")
        XCTAssertEqual(UnitConverter.format(8.04672), "8.05")
        XCTAssertEqual(UnitConverter.format(1609.344), "1609")
        XCTAssertEqual(UnitConverter.format(0.4536), "0.454")
    }
}

final class ErrorHintsTests: XCTestCase {
    func testCommonErrorsHaveHints() throws {
        let module = try XCTUnwrap(ErrorHints.hint(for: "ModuleNotFoundError: No module named 'requests'", targetLanguage: "ja"))
        XCTAssertTrue(module.cause.contains("requests"))
        XCTAssertEqual(module.fix, "仮想環境を確認し pip install requests")
        let port = try XCTUnwrap(ErrorHints.hint(for: "Error: listen EADDRINUSE: address already in use :::3000", targetLanguage: "en"))
        XCTAssertTrue(port.cause.contains("3000"))
        XCTAssertEqual(ErrorHints.hint(for: "zsh: command not found: pnpm", targetLanguage: "en")?.cause.contains("pnpm"), true)
        XCTAssertEqual(ErrorHints.hint(for: "bash: pnpm: command not found", targetLanguage: "en")?.cause.contains("pnpm"), true)
        XCTAssertNotNil(ErrorHints.hint(for: "TypeError: Cannot read properties of undefined (reading 'map')", targetLanguage: "ja"))
        XCTAssertNotNil(ErrorHints.hint(for: "CONFLICT (content): Merge conflict in README.md", targetLanguage: "ja"))
        XCTAssertNotNil(ErrorHints.hint(for: "Fatal error: Unexpectedly found nil while unwrapping an Optional value", targetLanguage: "en"))
    }

    func testSpecificBeatsGeneric() throws {
        let ssh = try XCTUnwrap(ErrorHints.hint(for: "git@github.com: Permission denied (publickey).", targetLanguage: "en"))
        XCTAssertTrue(ssh.cause.contains("SSH"))
    }

    func testUnknownErrorHasNoHint() {
        XCTAssertNil(ErrorHints.hint(for: "error: something unusual happened", targetLanguage: "ja"))
    }
}
