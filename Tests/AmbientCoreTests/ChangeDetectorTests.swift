import XCTest
@testable import AmbientCore

final class ChangeDetectorTests: XCTestCase {
    let base = GrayscaleFrame.filled(width: 160, height: 100, value: 40)

    func testIdenticalFramesProduceNoRegions() {
        var detector = ChangeDetector()
        XCTAssertTrue(detector.detect(previous: base, current: base).isEmpty)
    }

    func testSmallNoiseIsIgnored() {
        var detector = ChangeDetector()
        var pixels = base.pixels
        for i in stride(from: 0, to: pixels.count, by: 3) { pixels[i] = 40 + 10 }  // below threshold
        let noisy = GrayscaleFrame(width: 160, height: 100, pixels: pixels)!
        XCTAssertTrue(detector.detect(previous: base, current: noisy).isEmpty)
    }

    func testSingleCellChangeIsIgnored() {
        var detector = ChangeDetector()
        let blink = base.painting(x: 80, y: 40, width: 2, height: 6, value: 255)
        XCTAssertTrue(detector.detect(previous: base, current: blink).isEmpty)
    }

    func testBlockChangeIsLocalized() throws {
        var detector = ChangeDetector()
        let changed = base.painting(x: 16, y: 24, width: 40, height: 16, value: 220)
        let regions = detector.detect(previous: base, current: changed)
        XCTAssertEqual(regions.count, 1)
        let rect = try XCTUnwrap(regions.first).rect
        XCTAssertEqual(rect.minX, 16.0 / 160.0, accuracy: 0.01)
        XCTAssertEqual(rect.minY, 24.0 / 100.0, accuracy: 0.01)
        XCTAssertEqual(rect.width, 40.0 / 160.0, accuracy: 0.06)
        XCTAssertEqual(rect.height, 16.0 / 100.0, accuracy: 0.06)
    }

    func testNearbyRegionsAreMergedAndDistantOnesAreNot() {
        var detector = ChangeDetector()
        let changed = base
            .painting(x: 8, y: 8, width: 16, height: 8, value: 220)
            .painting(x: 32, y: 8, width: 16, height: 8, value: 220)    // 1 cell gap -> merged
            .painting(x: 120, y: 80, width: 24, height: 16, value: 220)  // far away
        let regions = detector.detect(previous: base, current: changed)
        XCTAssertEqual(regions.count, 2)
    }

    func testFullScreenChangeProducesSingleRegion() {
        var detector = ChangeDetector()
        let white = GrayscaleFrame.filled(width: 160, height: 100, value: 250)
        XCTAssertEqual(detector.detect(previous: base, current: white), [ChangedRegion(rect: .unit, confidence: 1)])
    }

    func testResolutionChangeReportsFullScreen() {
        var detector = ChangeDetector()
        let other = GrayscaleFrame.filled(width: 80, height: 50, value: 40)
        XCTAssertEqual(detector.detect(previous: base, current: other).first?.rect, .unit)
    }

    func testContinuouslyChangingAreaIsSuppressedThenReportedWhenSettled() {
        var detector = ChangeDetector()
        var previous = base
        var reports: [Int] = []
        // Simulate a video playing in the same area for 10 ticks.
        for tick in 0..<10 {
            let frame = base.painting(x: 40, y: 40, width: 32, height: 24, value: tick.isMultiple(of: 2) ? 200 : 90)
            reports.append(detector.detect(previous: previous, current: frame).count)
            previous = frame
        }
        XCTAssertEqual(reports.prefix(4), [1, 1, 1, 1], "early changes are reported")
        XCTAssertEqual(reports.suffix(5), [0, 0, 0, 0, 0], "volatile area is suppressed")

        // The video pauses: the final state is reported exactly once.
        XCTAssertEqual(detector.detect(previous: previous, current: previous).count, 1)
        XCTAssertEqual(detector.detect(previous: previous, current: previous).count, 0)
    }

    func testDownsampleFromBGRA() throws {
        // 4x2 image: left half white, right half black.
        var bytes = [UInt8]()
        for _ in 0..<2 {
            for x in 0..<4 {
                let v: UInt8 = x < 2 ? 255 : 0
                bytes += [v, v, v, 255]
            }
        }
        let frame = try XCTUnwrap(bytes.withUnsafeBytes { buffer in
            GrayscaleFrame.downsampled(bgra: buffer.baseAddress!, width: 4, height: 2, bytesPerRow: 16, targetWidth: 2)
        })
        XCTAssertEqual(frame.width, 2)
        XCTAssertEqual(frame.height, 1)
        XCTAssertEqual(frame.pixel(x: 0, y: 0), 255)
        XCTAssertEqual(frame.pixel(x: 1, y: 0), 0)
    }
}
