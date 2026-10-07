import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One pointer position in screen points (any origin), with its time.
public struct PointerSample: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let time: TimeInterval

    public init(x: Double, y: Double, time: TimeInterval) {
        self.x = x
        self.y = y
        self.time = time
    }
}

/// Recognizes "circle around something" drawn with the pointer
/// (SPEC LA-60). Pure geometry, so it is tested with recorded paths.
public struct CircleGestureRecognizer: Sendable {
    public var minimumDuration: TimeInterval = 0.25
    public var maximumDuration: TimeInterval = 4
    /// Diameter limits in points.
    public var minimumDiameter: Double = 30
    public var maximumDiameterRatio: Double = 0.8   // of the longer screen side
    /// The pointer must turn at least this much in total (≈ 300°).
    public var minimumTurning: Double = 300 * .pi / 180
    /// More than two loops is scribbling, not circling.
    public var maximumTurning: Double = 800 * .pi / 180
    /// The end of the stroke must come back this close to the start (× diameter).
    public var closureTolerance: Double = 0.4
    /// Radius spread (standard deviation ÷ mean) above this is not round.
    public var maximumRadiusVariation: Double = 0.4
    /// Narrow ellipses (short ÷ long side of the bounding box) are rejected.
    public var minimumRoundness: Double = 0.35
    /// Extra margin around the circled area (× its size).
    public var padding: Double = 0.1

    public init() {}

    /// The circled area normalized to the screen (top-left origin when the
    /// samples are), or nil when the stroke is not a circle.
    public func recognize(_ samples: [PointerSample], screenSize: CGSize) -> CGRect? {
        guard samples.count >= 8, let first = samples.first, let last = samples.last,
              screenSize.width > 0, screenSize.height > 0 else { return nil }
        let duration = last.time - first.time
        guard duration >= minimumDuration, duration <= maximumDuration else { return nil }

        let xs = samples.map(\.x)
        let ys = samples.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
        let width = maxX - minX
        let height = maxY - minY
        let diameter = max(width, height)
        guard diameter >= minimumDiameter,
              diameter <= maximumDiameterRatio * Double(max(screenSize.width, screenSize.height)),
              min(width, height) / diameter >= minimumRoundness else { return nil }

        // Closed: some point near the end returns to the start (allows overshoot).
        let tail = samples.suffix(max(2, samples.count / 4))
        let closest = tail.map { hypot($0.x - first.x, $0.y - first.y) }.min() ?? .infinity
        guard closest <= closureTolerance * diameter else { return nil }

        let turning = abs(Self.totalTurning(samples, minimumStep: max(2, diameter * 0.02)))
        guard turning >= minimumTurning, turning <= maximumTurning else { return nil }

        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        // Ellipses are fine: compare radii after scaling to a circle.
        let scaleX = diameter / max(width, 1)
        let scaleY = diameter / max(height, 1)
        let radii = samples.map { hypot(($0.x - centerX) * scaleX, ($0.y - centerY) * scaleY) }
        let mean = radii.reduce(0, +) / Double(radii.count)
        guard mean > 0 else { return nil }
        let variance = radii.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(radii.count)
        guard variance.squareRoot() / mean <= maximumRadiusVariation else { return nil }

        let padX = width * padding
        let padY = height * padding
        let rect = CGRect(
            x: (minX - padX) / Double(screenSize.width),
            y: (minY - padY) / Double(screenSize.height),
            width: (width + 2 * padX) / Double(screenSize.width),
            height: (height + 2 * padY) / Double(screenSize.height)
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Sum of signed direction changes along the path, ignoring jitter shorter than `minimumStep`.
    static func totalTurning(_ samples: [PointerSample], minimumStep: Double) -> Double {
        var points: [PointerSample] = []
        for sample in samples {
            if let previous = points.last, hypot(sample.x - previous.x, sample.y - previous.y) < minimumStep { continue }
            points.append(sample)
        }
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        var previousAngle: Double?
        for index in 1..<points.count {
            let angle = atan2(points[index].y - points[index - 1].y, points[index].x - points[index - 1].x)
            if let previousAngle {
                var delta = angle - previousAngle
                while delta > .pi { delta -= 2 * .pi }
                while delta < -.pi { delta += 2 * .pi }
                total += delta
            }
            previousAngle = angle
        }
        return total
    }
}

/// Collects the stroke while the trigger (⌥ held, no button pressed) is active
/// and recognizes it when the trigger is released.
public struct CircleGestureTracker: Sendable {
    public var recognizer = CircleGestureRecognizer()
    /// Older samples are dropped so a long hold cannot grow without bound.
    public var maximumSamples = 400
    /// A pause longer than this (pointer still while ⌥ is held) starts a new stroke.
    public var strokePause: TimeInterval = 0.5
    public private(set) var samples: [PointerSample] = []

    public init() {}

    /// The samples after the last pause, so resting before drawing doesn't count.
    static func lastStroke(_ samples: [PointerSample], pause: TimeInterval) -> [PointerSample] {
        guard samples.count > 1 else { return samples }
        var start = 0
        for index in 1..<samples.count where samples[index].time - samples[index - 1].time > pause {
            start = index
        }
        return Array(samples[start...])
    }

    public var isTracking: Bool { !samples.isEmpty }

    /// Feeds one poll. Returns the circled area (normalized) when a stroke ends as a circle.
    public mutating func update(position: CGPoint, time: TimeInterval, active: Bool, screenSize: CGSize) -> CGRect? {
        if active {
            if let last = samples.last, last.x == Double(position.x), last.y == Double(position.y) {
                return nil   // pointer resting; keep the stroke compact
            }
            samples.append(PointerSample(x: Double(position.x), y: Double(position.y), time: time))
            if samples.count > maximumSamples { samples.removeFirst(samples.count - maximumSamples) }
            // Only the last few seconds can form one gesture.
            if let first = samples.first, time - first.time > recognizer.maximumDuration * 2 {
                samples.removeAll { time - $0.time > recognizer.maximumDuration }
            }
            return nil
        }
        guard !samples.isEmpty else { return nil }
        defer { samples.removeAll() }
        return recognizer.recognize(Self.lastStroke(samples, pause: strokePause), screenSize: screenSize)
    }

    public mutating func cancel() {
        samples.removeAll()
    }
}
