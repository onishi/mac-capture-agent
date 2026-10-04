import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where the HUD should appear.
public enum HUDPosition: String, Sendable, CaseIterable, Identifiable {
    /// Next to the text it explains, without covering it.
    case nearTarget
    /// Fixed in the top-right corner of the screen.
    case topRight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .nearTarget: return "Near the text"
        case .topRight: return "Top right corner"
        }
    }
}

/// Computes the HUD frame. All rects use AppKit screen coordinates
/// (points, bottom-left origin) except `anchor`, which is normalized to the
/// captured display with a top-left origin (as produced by OCR).
public struct HUDPlacement: Sendable, Equatable {
    /// Distance from the screen's visible edges.
    public var margin: CGFloat = 12
    /// Gap between the target text and the HUD.
    public var gap: CGFloat = 8

    public init() {}

    /// Converts a normalized top-left anchor to an AppKit rect on `screenFrame`.
    public static func screenRect(forAnchor anchor: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + anchor.minX * screenFrame.width,
            y: screenFrame.maxY - anchor.maxY * screenFrame.height,
            width: anchor.width * screenFrame.width,
            height: anchor.height * screenFrame.height
        )
    }

    public func frame(
        size: CGSize,
        anchor: CGRect?,
        position: HUDPosition,
        screenFrame: CGRect,
        visibleFrame: CGRect
    ) -> CGRect {
        let topRight = CGRect(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.maxY - size.height - margin,
            width: size.width,
            height: size.height
        )
        guard position == .nearTarget, let anchor, anchor.width > 0, anchor.height > 0 else {
            return topRight
        }

        let target = Self.screenRect(forAnchor: anchor, screenFrame: screenFrame)
        let bounds = visibleFrame.insetBy(dx: margin, dy: margin)
        guard bounds.width >= size.width, bounds.height >= size.height else { return topRight }

        let x = clamp(target.minX, bounds.minX, bounds.maxX - size.width)
        // Prefer below the text (reading continues downward), then above,
        // then to the right/left of it. Never cover the text.
        let candidates = [
            CGRect(x: x, y: target.minY - gap - size.height, width: size.width, height: size.height),
            CGRect(x: x, y: target.maxY + gap, width: size.width, height: size.height),
            CGRect(x: target.maxX + gap, y: clamp(target.maxY - size.height, bounds.minY, bounds.maxY - size.height), width: size.width, height: size.height),
            CGRect(x: target.minX - gap - size.width, y: clamp(target.maxY - size.height, bounds.minY, bounds.maxY - size.height), width: size.width, height: size.height)
        ]
        for candidate in candidates where bounds.contains(candidate) && !candidate.intersects(target) {
            return candidate
        }
        return topRight
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), Swift.max(lower, upper))
    }
}

/// Geometry for the HUD chrome (reticle + leader line). Coordinates are in the
/// overlay view's space (top-left origin), but the math is orientation agnostic.
public enum HUDGeometry {
    /// Leader line from the target corner closest to the card, to the closest
    /// point on the card's edge. `nil` when the rects overlap.
    public static func leaderLine(from target: CGRect, to card: CGRect) -> (start: CGPoint, end: CGPoint)? {
        guard !target.intersects(card) else { return nil }
        let corners = [
            CGPoint(x: target.minX, y: target.minY), CGPoint(x: target.maxX, y: target.minY),
            CGPoint(x: target.minX, y: target.maxY), CGPoint(x: target.maxX, y: target.maxY)
        ]
        let candidates = corners.map { corner -> (CGPoint, CGPoint, CGFloat) in
            let end = closestPoint(on: card, to: corner)
            return (corner, end, hypot(end.x - corner.x, end.y - corner.y))
        }
        guard let best = candidates.min(by: { $0.2 < $1.2 }) else { return nil }
        return (best.0, best.1)
    }

    public static func closestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(x: Swift.min(Swift.max(point.x, rect.minX), rect.maxX),
                y: Swift.min(Swift.max(point.y, rect.minY), rect.maxY))
    }

    /// Converts an AppKit screen rect (bottom-left origin) into the top-left
    /// coordinate space of an overlay covering `screenFrame`.
    public static func viewRect(fromScreenRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }
}

public extension HUDPlacement {
    /// Grows `frame` (AppKit coordinates) by `extraHeight` while keeping its top
    /// edge fixed, so the card doesn't move under the pointer when its actions
    /// appear. Shifts up only as much as needed to stay inside `visibleFrame`.
    func grow(_ frame: CGRect, byHeight extraHeight: CGFloat, within visibleFrame: CGRect) -> CGRect {
        var grown = CGRect(x: frame.minX, y: frame.minY - extraHeight, width: frame.width, height: frame.height + extraHeight)
        let bottom = visibleFrame.minY + margin
        if grown.minY < bottom {
            grown.origin.y = Swift.min(bottom, visibleFrame.maxY - grown.height)
        }
        return grown
    }
}
