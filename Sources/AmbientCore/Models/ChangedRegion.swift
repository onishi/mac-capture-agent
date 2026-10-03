import Foundation

/// A part of the screen that changed between two frames.
///
/// `rect` is expressed in normalized coordinates (0...1) with a **top-left**
/// origin, so it is independent of the capture resolution.
public struct ChangedRegion: Sendable, Equatable {
    public let rect: CGRect
    public let confidence: Double

    public init(rect: CGRect, confidence: Double) {
        self.rect = rect
        self.confidence = min(max(confidence, 0), 1)
    }

    /// Returns a region grown by the given normalized margins and clamped to the unit square.
    public func expanded(dx: CGFloat, dy: CGFloat) -> ChangedRegion {
        ChangedRegion(rect: rect.insetBy(dx: -dx, dy: -dy).clampedToUnit(), confidence: confidence)
    }

    public var area: CGFloat { rect.width * rect.height }
}

public extension CGRect {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Clamps the rect to the normalized unit square.
    func clampedToUnit() -> CGRect {
        let minX = Swift.max(0, Swift.min(1, self.minX))
        let minY = Swift.max(0, Swift.min(1, self.minY))
        let maxX = Swift.max(minX, Swift.min(1, self.maxX))
        let maxY = Swift.max(minY, Swift.min(1, self.maxY))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Distance between the edges of two rects (0 when they touch or overlap).
    func gap(to other: CGRect) -> CGFloat {
        let dx = Swift.max(0, Swift.max(other.minX - maxX, minX - other.maxX))
        let dy = Swift.max(0, Swift.max(other.minY - maxY, minY - other.maxY))
        return Swift.max(dx, dy)
    }
}

public enum RegionMerger {
    /// Merges regions whose edges are closer than `distance` (normalized units).
    /// The confidence of a merged region is the maximum of its parts.
    public static func merge(_ regions: [ChangedRegion], within distance: CGFloat) -> [ChangedRegion] {
        var result = regions
        var mergedSomething = true
        while mergedSomething {
            mergedSomething = false
            outer: for i in result.indices {
                for j in result.indices where j > i {
                    if result[i].rect.gap(to: result[j].rect) <= distance {
                        let merged = ChangedRegion(
                            rect: result[i].rect.union(result[j].rect),
                            confidence: max(result[i].confidence, result[j].confidence)
                        )
                        result.remove(at: j)
                        result[i] = merged
                        mergedSomething = true
                        break outer
                    }
                }
            }
        }
        return result
    }
}
