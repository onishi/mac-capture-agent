import Foundation

/// Trade-off between responsiveness and battery/CPU usage.
public enum PerformanceMode: String, Sendable, CaseIterable, Identifiable {
    case battery
    case balanced
    case performance

    public var id: String { rawValue }

    /// Frames per second requested from ScreenCaptureKit.
    public var captureFramesPerSecond: Int {
        switch self {
        case .battery: return 5
        case .balanced: return 15
        case .performance: return 30
        }
    }

    /// Interval between two change-detection passes.
    public var changeDetectionInterval: TimeInterval {
        switch self {
        case .battery: return 1.0
        case .balanced: return 0.5
        case .performance: return 0.25
        }
    }

    /// Minimum interval between two OCR / vision passes.
    public var visionInterval: TimeInterval {
        switch self {
        case .battery: return 2.0
        case .balanced: return 1.0
        case .performance: return 0.5
        }
    }

    /// Minimum interval between two image classification passes.
    public var classificationInterval: TimeInterval { visionInterval * 5 }

    public var displayName: String {
        switch self {
        case .battery: return "Battery"
        case .balanced: return "Balanced"
        case .performance: return "Performance"
        }
    }
}
