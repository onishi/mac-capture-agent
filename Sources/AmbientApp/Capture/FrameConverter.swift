import CoreGraphics
import CoreVideo
import Foundation

enum FrameConverter {
    /// Creates a small luminance thumbnail from a BGRA pixel buffer.
    static func grayscale(from pixelBuffer: CVPixelBuffer, targetWidth: Int = 320) -> GrayscaleFrame? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        return GrayscaleFrame.downsampled(
            bgra: UnsafeRawPointer(base),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            targetWidth: targetWidth
        )
    }

    /// Converts a normalized top-left-origin rect to Vision's normalized bottom-left-origin rect.
    static func visionRect(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a Vision bounding box that is relative to `regionOfInterest`
    /// (both bottom-left origin) into a top-left-origin rect normalized to the full image.
    static func topLeftRect(fromVisionBox box: CGRect, regionOfInterest roi: CGRect) -> CGRect {
        let x = roi.minX + box.minX * roi.width
        let bottom = roi.minY + box.minY * roi.height
        let width = box.width * roi.width
        let height = box.height * roi.height
        return CGRect(x: x, y: 1 - (bottom + height), width: width, height: height)
    }
}
