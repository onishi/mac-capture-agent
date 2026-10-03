import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

final class TextBlockGrouperTests: XCTestCase {
    func testJoinsWrappedLines() {
        let lines = [
            RecognizedTextRegion(text: "Nous sommes heureux de vous", boundingBox: CGRect(x: 0.1, y: 0.30, width: 0.3, height: 0.02), confidence: 0.9),
            RecognizedTextRegion(text: "accueillir aujourd'hui.", boundingBox: CGRect(x: 0.1, y: 0.325, width: 0.25, height: 0.02), confidence: 0.7),
            RecognizedTextRegion(text: "Menu", boundingBox: CGRect(x: 0.7, y: 0.05, width: 0.05, height: 0.02), confidence: 0.9)
        ]
        let blocks = TextBlockGrouper().group(lines)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.last?.text, "Nous sommes heureux de vous accueillir aujourd'hui.")
        XCTAssertEqual(Double(blocks.last?.confidence ?? 0), 0.8, accuracy: 0.001)
    }

    func testDoesNotJoinDistantLines() {
        let lines = [
            RecognizedTextRegion(text: "First paragraph", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.02), confidence: 0.9),
            RecognizedTextRegion(text: "Second paragraph", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.02), confidence: 0.9)
        ]
        XCTAssertEqual(TextBlockGrouper().group(lines).count, 2)
    }

    func testJoinRules() {
        XCTAssertEqual(TextBlockGrouper.join("infor-", "mation"), "information")
        XCTAssertEqual(TextBlockGrouper.join("我们明天", "去北京"), "我们明天去北京")
        XCTAssertEqual(TextBlockGrouper.join("hello", "world"), "hello world")
    }
}

final class PrivacyPolicyTests: XCTestCase {
    func testExcludesPasswordManagersAndSensitiveTitles() {
        let policy = PrivacyPolicy()
        XCTAssertFalse(policy.allowsAnalysis(bundleIdentifier: "com.1password.1password", windowTitle: nil))
        XCTAssertFalse(policy.allowsAnalysis(bundleIdentifier: "com.apple.Safari", windowTitle: "Change Password – Example"))
        XCTAssertFalse(policy.allowsAnalysis(bundleIdentifier: "com.apple.Safari", windowTitle: "パスワードの変更"))
        XCTAssertTrue(policy.allowsAnalysis(bundleIdentifier: "com.apple.Safari", windowTitle: "Le Monde"))
        XCTAssertTrue(policy.allowsAnalysis(bundleIdentifier: nil, windowTitle: nil))
    }
}

final class VisualCategoryMapperTests: XCTestCase {
    func testMapsVisionLabels() {
        XCTAssertEqual(VisualCategoryMapper.category(for: "dog"), .animal)
        XCTAssertEqual(VisualCategoryMapper.category(for: "flower_rose"), .plant)
        XCTAssertEqual(VisualCategoryMapper.category(for: "baked_goods"), .food)
        XCTAssertEqual(VisualCategoryMapper.category(for: "tower"), .landmark)
        XCTAssertEqual(VisualCategoryMapper.category(for: "people"), .person)
        XCTAssertEqual(VisualCategoryMapper.category(for: "document"), .text)
        XCTAssertEqual(VisualCategoryMapper.category(for: "sky"), .unknown)
    }

    func testCategoriesAreUniqueAndFiltered() {
        let labels: [(label: String, confidence: Float)] = [("cat", 0.9), ("dog", 0.8), ("tree", 0.2), ("sky", 0.9)]
        XCTAssertEqual(VisualCategoryMapper.categories(for: labels), [.animal])
    }
}

final class PerformanceModeTests: XCTestCase {
    func testRatesMatchSpecification() {
        XCTAssertEqual(PerformanceMode.battery.captureFramesPerSecond, 5)
        XCTAssertEqual(PerformanceMode.balanced.captureFramesPerSecond, 15)
        XCTAssertEqual(PerformanceMode.performance.captureFramesPerSecond, 30)
        XCTAssertEqual(1 / PerformanceMode.battery.visionInterval, 0.5)
        XCTAssertEqual(1 / PerformanceMode.balanced.visionInterval, 1)
        XCTAssertEqual(1 / PerformanceMode.performance.visionInterval, 2)
        XCTAssertEqual(1 / PerformanceMode.balanced.changeDetectionInterval, 2)
    }
}
