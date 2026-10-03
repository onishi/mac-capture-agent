import CoreGraphics
import CoreVideo
import Foundation

/// A frame delivered by ScreenCaptureKit. The pixel buffer is IOSurface backed
/// and lives only in memory; it is never written to disk.
struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    /// Seconds since boot (`ProcessInfo.systemUptime`), monotonic.
    let timestamp: TimeInterval
    let displayID: CGDirectDisplayID
}
