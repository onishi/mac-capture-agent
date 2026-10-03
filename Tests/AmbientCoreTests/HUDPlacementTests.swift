import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import AmbientCore

final class HUDPlacementTests: XCTestCase {
    // 1000x800 display; menu bar takes the top 25pt.
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 775)
    let size = CGSize(width: 300, height: 100)
    let placement = HUDPlacement()

    func testAnchorConversionFlipsYAxis() {
        let rect = HUDPlacement.screenRect(forAnchor: CGRect(x: 0.1, y: 0.25, width: 0.2, height: 0.05), screenFrame: screen)
        XCTAssertEqual(rect, CGRect(x: 100, y: 560, width: 200, height: 40))
    }

    func testTopRightWithoutAnchor() {
        let frame = placement.frame(size: size, anchor: nil, position: .nearTarget, screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: 688, y: 663, width: 300, height: 100))
    }

    func testTopRightWhenRequested() {
        let anchor = CGRect(x: 0.1, y: 0.4, width: 0.3, height: 0.03)
        let frame = placement.frame(size: size, anchor: anchor, position: .topRight, screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(frame.origin, CGPoint(x: 688, y: 663))
    }

    func testPrefersBelowTheText() {
        let anchor = CGRect(x: 0.1, y: 0.25, width: 0.2, height: 0.05) // AppKit y 560...600
        let frame = placement.frame(size: size, anchor: anchor, position: .nearTarget, screenFrame: screen, visibleFrame: visible)
        XCTAssertEqual(frame, CGRect(x: 100, y: 452, width: 300, height: 100))
    }

    func testGoesAboveWhenNoRoomBelow() {
        let anchor = CGRect(x: 0.5, y: 0.9, width: 0.2, height: 0.05) // near the bottom
        let frame = placement.frame(size: size, anchor: anchor, position: .nearTarget, screenFrame: screen, visibleFrame: visible)
        let target = HUDPlacement.screenRect(forAnchor: anchor, screenFrame: screen)
        XCTAssertGreaterThanOrEqual(frame.minY, target.maxY)
        XCTAssertFalse(frame.intersects(target))
    }

    func testStaysOnScreenAndNeverCoversText() {
        for x in stride(from: 0.0, through: 0.9, by: 0.15) {
            for y in stride(from: 0.0, through: 0.9, by: 0.15) {
                let anchor = CGRect(x: x, y: y, width: 0.1, height: 0.04)
                let frame = placement.frame(size: size, anchor: anchor, position: .nearTarget, screenFrame: screen, visibleFrame: visible)
                XCTAssertTrue(visible.contains(frame), "\(anchor)")
                XCTAssertFalse(frame.intersects(HUDPlacement.screenRect(forAnchor: anchor, screenFrame: screen)), "\(anchor)")
            }
        }
    }

    func testSecondaryDisplayOffset() {
        let second = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let anchor = CGRect(x: 0.1, y: 0.25, width: 0.2, height: 0.05)
        let frame = placement.frame(size: size, anchor: anchor, position: .nearTarget, screenFrame: second, visibleFrame: second)
        XCTAssertEqual(frame.minX, 1100)
    }
}

final class HUDGeometryTests: XCTestCase {
    func testLeaderLineConnectsNearestCornerToCardEdge() throws {
        let target = CGRect(x: 100, y: 100, width: 200, height: 40)
        let card = CGRect(x: 100, y: 160, width: 300, height: 120)  // below (top-left space)
        let line = try XCTUnwrap(HUDGeometry.leaderLine(from: target, to: card))
        XCTAssertEqual(line.start.y, 140)
        XCTAssertEqual(line.end.y, 160)
        XCTAssertNil(HUDGeometry.leaderLine(from: target, to: target.insetBy(dx: 10, dy: 10)))
    }

    func testViewRectConversion() {
        let screen = CGRect(x: 1000, y: 0, width: 1000, height: 800)
        let rect = HUDGeometry.viewRect(fromScreenRect: CGRect(x: 1100, y: 600, width: 50, height: 100), screenFrame: screen)
        XCTAssertEqual(rect, CGRect(x: 100, y: 100, width: 50, height: 100))
    }
}
