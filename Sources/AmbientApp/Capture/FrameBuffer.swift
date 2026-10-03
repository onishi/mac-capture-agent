import CoreVideo
import Foundation

/// A captured frame prepared for analysis.
struct AnalyzableFrame: @unchecked Sendable {
    /// Small luminance copy used for change detection.
    let gray: GrayscaleFrame
    /// Full resolution pixels, used only for OCR/classification of changed regions.
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval
}

/// Holds the previous and the current frame. Only the current frame keeps its
/// full resolution pixel buffer; the previous one is reduced to its luminance
/// thumbnail to keep memory low. Nothing is ever persisted.
actor FrameBuffer {
    private(set) var previousFrame: GrayscaleFrame?
    private(set) var currentFrame: AnalyzableFrame?

    var timestamp: TimeInterval? { currentFrame?.timestamp }

    /// Stores `frame` as current and returns the previous thumbnail (if any).
    func push(_ frame: AnalyzableFrame) -> GrayscaleFrame? {
        previousFrame = currentFrame?.gray
        currentFrame = frame
        return previousFrame
    }

    func reset() {
        previousFrame = nil
        currentFrame = nil
    }
}
