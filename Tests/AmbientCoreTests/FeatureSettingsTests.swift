import XCTest
@testable import AmbientCore

final class FeatureSettingsTests: XCTestCase {
    func candidate(_ action: SuggestedAction, importance: Double, _ payload: String = "x") -> RoutedAction {
        RoutedAction(action: action, confidence: 0.8, importance: importance, region: nil, payload: payload)
    }

    func testDefaultsEverythingOnInDefaultOrder() {
        let settings = FeatureSettings.default
        XCTAssertTrue(IntelFeature.allCases.allSatisfy(settings.isEnabled))
        XCTAssertEqual(settings.order, IntelFeature.rankable)
        XCTAssertEqual(settings.rank(of: .qrCode), 0)
        XCTAssertEqual(settings.rank(of: .briefing), IntelFeature.rankable.count, "non-rankable ranks last")
    }

    func testRouterActionsMapToFeatures() {
        XCTAssertEqual(IntelFeature(action: .translate), .translation)
        XCTAssertEqual(IntelFeature(action: .identifyPlant), .identification)
        XCTAssertEqual(IntelFeature(action: .identifyPerson), .publicFigure)
        XCTAssertNil(IntelFeature(action: .ignore))
    }

    func testPriorityDecidesBetweenShowableCandidates() {
        let translation = candidate(.translate, importance: 0.95)
        let error = candidate(.explainError, importance: 0.75)
        var settings = FeatureSettings.default
        XCTAssertEqual(settings.select(from: [translation, error]).selected, error, "errors rank above translation by default")
        settings.move(.translation, up: true)   // translation above errors
        XCTAssertEqual(settings.order.prefix(3), [.qrCode, .translation, .errorExplanation])
        XCTAssertEqual(settings.select(from: [translation, error]).selected, translation)
    }

    func testPriorityNeverLiftsCandidatesBelowTheShowThreshold() {
        let weakError = candidate(.explainError, importance: 0.3)
        let translation = candidate(.translate, importance: 0.9)
        XCTAssertEqual(FeatureSettings.default.select(from: [weakError, translation]).selected, translation)
        XCTAssertEqual(FeatureSettings.default.select(from: [weakError]).selected, .ignore)
    }

    func testDisabledFeaturesAreDroppedEverywhere() {
        var settings = FeatureSettings.default
        settings.set(.translation, enabled: false)
        let translation = candidate(.translate, importance: 0.95)
        let decision = settings.select(from: [translation])
        XCTAssertEqual(decision.selected, .ignore)
        XCTAssertTrue(decision.candidates.isEmpty, "not even offered to the LLM router")
        XCTAssertEqual(settings.ordered([.translation, .qrCode, .unitConversion]), [.qrCode, .unitConversion])
        settings.set(.translation, enabled: true)
        XCTAssertTrue(settings.isEnabled(.translation))
    }

    func testOrderedIsStableForNonRankable() {
        XCTAssertEqual(FeatureSettings.default.ordered([.glossary, .unitConversion, .qrCode, .briefing]),
                       [.qrCode, .unitConversion, .glossary, .briefing])
    }

    func testMoveStopsAtTheEnds() {
        var settings = FeatureSettings.default
        settings.move(.qrCode, up: true)
        XCTAssertEqual(settings.order, IntelFeature.rankable)
        settings.move(.regionSummary, up: false)
        XCTAssertEqual(settings.order, IntelFeature.rankable)
        settings.move(.briefing, up: true)
        XCTAssertEqual(settings.order, IntelFeature.rankable, "non-rankable can't be moved")
        settings.move(.regionSummary, up: true)
        settings.resetOrder()
        XCTAssertEqual(settings.order, IntelFeature.rankable)
    }

    func testCodableRoundTripAndForwardCompatibility() throws {
        var settings = FeatureSettings.default
        settings.set(.briefing, enabled: false)
        settings.move(.castOnScreen, up: true)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)

        // Unknown names are ignored, missing features are appended, duplicates dropped.
        let old = #"{"disabled":["translation","futureThing"],"order":["translation","translation","qrCode","briefing"]}"#
        let migrated = try JSONDecoder().decode(FeatureSettings.self, from: Data(old.utf8))
        XCTAssertEqual(migrated.disabled, [.translation])
        XCTAssertEqual(Array(migrated.order.prefix(2)), [.translation, .qrCode])
        XCTAssertEqual(Set(migrated.order), Set(IntelFeature.rankable))
        XCTAssertEqual(migrated.order.count, IntelFeature.rankable.count)
    }

    func testEveryFeatureHasATitle() {
        XCTAssertTrue(IntelFeature.allCases.allSatisfy { !$0.title.isEmpty })
        XCTAssertTrue(IntelFeature.regionSummary.requiresLanguageModel)
        XCTAssertFalse(IntelFeature.unitConversion.requiresLanguageModel)
    }
}

final class CirclePlannerPriorityTests: XCTestCase {
    func testUserOrderAndDisabledFeaturesApplyToCircleLookup() {
        let foreign = RoutedAction(action: .translate, confidence: 0.9, importance: 0.2, region: nil, payload: "Guten Morgen, wie geht es dir heute?")
        let error = RoutedAction(action: .explainError, confidence: 0.8, importance: 0.2, region: nil, payload: "Fehler: x")
        var settings = FeatureSettings.default
        let plan = { ActiveLookupPlanner.plan(qrPayloads: [], candidates: [foreign, error], text: "Guten Morgen, wie geht es dir heute?",
                                              conversions: [], categories: [], canUseLanguageModel: true, features: settings) }
        XCTAssertEqual(plan(), .explainError(error))
        settings.move(.translation, up: true)
        XCTAssertEqual(plan(), .translate(foreign))
        settings.set(.translation, enabled: false)
        XCTAssertEqual(plan(), .explainError(error))
        settings.set(.errorExplanation, enabled: false)
        XCTAssertEqual(plan(), .describe("Guten Morgen, wie geht es dir heute?"))
        settings.set(.regionSummary, enabled: false)
        XCTAssertEqual(plan(), .nothing)
    }
}

final class AIAnswerRecordTests: XCTestCase {
    func testClipsAndCollapses() {
        let record = AIAnswerRecord(feature: .termExplanation, subject: "RAG\n  term", answer: String(repeating: "あ", count: 700),
                                    outcome: .shown, durationMilliseconds: -5)
        XCTAssertEqual(record.subject, "RAG term")
        XCTAssertEqual(record.answer.count, AIAnswerRecord.maximumAnswerLength)
        XCTAssertTrue(record.answer.hasSuffix("…"))
        XCTAssertEqual(record.durationMilliseconds, 0)
    }

    func testMatches() {
        let record = AIAnswerRecord(feature: .identification, subject: "kingfisher", answer: "カワセミかもしれません", outcome: .filtered)
        XCTAssertTrue(record.matches(""))
        XCTAssertTrue(record.matches("カワセミ"))
        XCTAssertTrue(record.matches("KINGFISHER"))
        XCTAssertTrue(record.matches("identification"))
        XCTAssertFalse(record.matches("RAG"))
    }
}
