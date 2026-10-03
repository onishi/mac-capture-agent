import XCTest
@testable import AmbientCore

final class CooldownCacheTests: XCTestCase {
    func testBlocksRepeatsWithinDuration() {
        var cache = CooldownCache(duration: 300)
        XCTAssertTrue(cache.checkAndRecord("a", now: 0))
        XCTAssertFalse(cache.checkAndRecord("a", now: 10))
        XCTAssertFalse(cache.checkAndRecord("a", now: 299))
        XCTAssertTrue(cache.checkAndRecord("a", now: 300))
        XCTAssertTrue(cache.checkAndRecord("b", now: 10))
    }

    func testKeyNormalizesOCRNoise() {
        let a = CooldownCache.key(action: .translate, payload: "Je suis  ici.")
        let b = CooldownCache.key(action: .translate, payload: "je suis ici")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, CooldownCache.key(action: .explainTerm, payload: "je suis ici"))
    }

    func testPrunesToMaximumEntries() {
        var cache = CooldownCache(duration: 1_000, maximumEntries: 3)
        for i in 0..<10 { cache.record("k\(i)", now: Double(i)) }
        XCTAssertLessThanOrEqual(cache.count, 3)
        XCTAssertTrue(cache.isCoolingDown("k9", now: 10), "most recent entries are kept")
        XCTAssertFalse(cache.isCoolingDown("k0", now: 10))
    }

    func testHUDMessageDuplicateAndDuration() {
        let a = HUDMessage(kind: .translation, title: "French", original: "Je suis ici.", detail: "私はここにいます。", anchor: nil)
        let b = HUDMessage(kind: .translation, title: "French", original: "Je suis ici.", detail: "私はここにいます。", anchor: nil)
        XCTAssertTrue(a.isDuplicate(of: b))
        XCTAssertFalse(a.isDuplicate(of: nil))
        XCTAssertGreaterThanOrEqual(a.displayDuration, 3)
        let long = HUDMessage(kind: .translation, title: "", original: String(repeating: "a", count: 2_000), detail: "", anchor: nil)
        XCTAssertEqual(long.displayDuration, 6)
    }

    func testTranslationValidator() {
        XCTAssertFalse(TranslationResultValidator.isUseful(original: "Hello world", translated: " hello  world "))
        XCTAssertFalse(TranslationResultValidator.isUseful(original: "Hello world", translated: ""))
        XCTAssertTrue(TranslationResultValidator.isUseful(original: "Hello world", translated: "こんにちは世界"))
    }
}
