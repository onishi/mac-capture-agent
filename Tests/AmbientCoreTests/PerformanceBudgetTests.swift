import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

/// Performance regression guards for the per-frame hot path (PF-1).
///
/// Budgets are about 5× the debug-build time measured on a Linux CI-class
/// machine (release builds are 10–20× faster still), so they only fail on a
/// real regression, such as recompiling a regex per line or allocating
/// inside the pixel loop — both found and fixed with these tests. Real numbers come from Instruments on a Mac
/// (docs/CHECKLIST.md).
final class PerformanceBudgetTests: XCTestCase {
    /// Average seconds per call of `body` over `iterations`.
    private func averageSeconds(iterations: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsed) / 1_000_000_000 / Double(iterations)
    }

    func testDownsamplingA5KFrameStaysCheap() throws {
        // 5K Retina BGRA buffer → 320-px luminance thumbnail, once per frame.
        let width = 5120, height = 2880, bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for i in stride(from: 0, to: buffer.count, by: 97) { buffer[i] = UInt8(i % 251) }
        let seconds = buffer.withUnsafeBytes { raw -> Double in
            guard let base = raw.baseAddress else { return .infinity }
            return averageSeconds(iterations: 20) {
                _ = GrayscaleFrame.downsampled(bgra: base, width: width, height: height, bytesPerRow: bytesPerRow, targetWidth: 320)
            }
        }
        XCTAssertLessThan(seconds, 0.25, "downsampling took \(seconds * 1000) ms")
    }

    func testChangeDetectionPerFrame() {
        let base = GrayscaleFrame.filled(width: 320, height: 180, value: 40)
        let frames = (0..<8).map { i in
            base.painting(x: 20 + i * 30, y: 10 + i * 15, width: 60, height: 24, value: 220)
        }
        var detector = ChangeDetector()
        var previous = base
        var index = 0
        let seconds = averageSeconds(iterations: 100) {
            let current = frames[index % frames.count]
            _ = detector.detect(previous: previous, current: current)
            previous = current
            index += 1
        }
        XCTAssertLessThan(seconds, 0.05, "change detection took \(seconds * 1000) ms")
    }

    func testSensitiveScanOfAFullScreenOfText() {
        // ~80 OCR lines of ordinary prose and code, scanned before anything else.
        let lines = (0..<80).map { i in
            textRegion("let value\(i) = compute(input: \(i * 37), mode: .fast) // returns the cached result \(i)",
                       y: CGFloat(i) / 90)
        }
        let detector = SensitiveDataDetector()
        let seconds = averageSeconds(iterations: 50) {
            _ = detector.partition(lines)
        }
        XCTAssertLessThan(seconds, 0.02, "sensitive scan took \(seconds * 1000) ms")
    }

    func testRoutingAFullScreenOfText() {
        let lines = (0..<80).map { i in
            textRegion("Ceci est la ligne numéro \(i) d'un article assez long sur la politique européenne.", y: CGFloat(i) / 90)
        }
        let router = AIRouter(detector: ForeignTextDetector(
            identifier: StubLanguageIdentifier(fallback: LanguageGuess(code: "fr", confidence: 0.95)),
            configuration: ForeignTextDetectorConfiguration(userLanguage: "ja")
        ))
        let ctx = context(lines)
        let seconds = averageSeconds(iterations: 50) {
            _ = router.decide(ctx)
        }
        XCTAssertLessThan(seconds, 0.15, "routing took \(seconds * 1000) ms")
    }

    func testErrorDetectionOnALongLog() {
        let log = (0..<200).map { "[\($0)] Compiling module step \($0) of 200 … ok" }.joined(separator: "\n")
        let detector = ErrorDetector()
        let seconds = averageSeconds(iterations: 50) {
            _ = detector.detect(in: log)
        }
        XCTAssertLessThan(seconds, 0.06, "error detection took \(seconds * 1000) ms")
    }

    func testClusteringADayOfPageVisits() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let topics = ["swift concurrency", "grdb migrations", "rust ownership", "tokyo travel", "camera review"]
        let visits = (0..<600).map { i -> PageVisit in
            let title = "\(topics[(i / 20) % topics.count]) part \(i % 7)"
            let begin = start.addingTimeInterval(Double(i) * 60)
            return PageVisit(key: PageKey(bundleIdentifier: "com.apple.Safari", windowTitle: title, url: nil),
                             application: "Safari", bundleIdentifier: "com.apple.Safari",
                             title: title, url: nil, start: begin, end: begin.addingTimeInterval(50))
        }
        let clusterer = WorkSessionClusterer()
        let seconds = averageSeconds(iterations: 3) {
            _ = clusterer.cluster(visits)
        }
        XCTAssertLessThan(seconds, 0.5, "clustering took \(seconds * 1000) ms")
    }
}
