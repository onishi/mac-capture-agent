import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Detects when the pointer rests in one place (an "Interest Region"), the
/// stand-in for eye tracking. Pure: feed positions with timestamps.
public struct PointerDwellTracker: Sendable {
    /// Movement within this radius (normalized screen units) still counts as resting.
    public var radius: CGFloat = 0.015
    /// Resting this long triggers a dwell.
    public var duration: TimeInterval = 2.0

    private var anchor: CGPoint?
    private var since: TimeInterval = 0
    private var fired = false

    public init() {}

    /// - Returns: the dwell point once per rest, when it reaches `duration`.
    public mutating func update(position: CGPoint, at time: TimeInterval) -> CGPoint? {
        if let anchor, hypot(position.x - anchor.x, position.y - anchor.y) <= radius {
            if !fired, time - since >= duration {
                fired = true
                return anchor
            }
            return nil
        }
        anchor = position
        since = time
        fired = false
        return nil
    }

    public mutating func reset() {
        anchor = nil
        fired = false
    }

    /// The region analyzed around a dwell point: wide (code lines are long), clamped to the screen.
    public static func region(around point: CGPoint, width: CGFloat = 0.45, height: CGFloat = 0.22) -> CGRect {
        CGRect(x: point.x - width * 0.35, y: point.y - height / 2, width: width, height: height).clampedToUnit()
    }
}
