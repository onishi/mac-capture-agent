import Foundation

/// A small 8-bit luminance image used for cheap change detection.
public struct GrayscaleFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init?(width: Int, height: Int, pixels: [UInt8]) {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    @inline(__always)
    public func pixel(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    /// Builds a downsampled luminance frame from a 32-bit BGRA buffer
    /// (the pixel format delivered by ScreenCaptureKit).
    ///
    /// Each output pixel averages 4 samples inside its source block, which is
    /// cheap but still robust to single-pixel noise.
    public static func downsampled(
        bgra base: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        targetWidth: Int
    ) -> GrayscaleFrame? {
        guard width > 0, height > 0, targetWidth > 0, bytesPerRow >= width * 4 else { return nil }
        let outWidth = min(targetWidth, width)
        let outHeight = max(1, Int((Double(height) * Double(outWidth) / Double(width)).rounded()))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var output = [UInt8](repeating: 0, count: outWidth * outHeight)

        // Byte offsets of the two sample columns of every output column,
        // computed once per frame (no allocation inside the pixel loop).
        var leftColumns = [Int](repeating: 0, count: outWidth)
        var rightColumns = [Int](repeating: 0, count: outWidth)
        for tx in 0..<outWidth {
            let x0 = tx * width / outWidth
            let x1 = max(x0 + 1, (tx + 1) * width / outWidth)
            leftColumns[tx] = min(x0 + (x1 - x0) / 4, width - 1) * 4
            rightColumns[tx] = min(x0 + 3 * (x1 - x0) / 4, width - 1) * 4
        }

        @inline(__always) func luma(_ offset: Int) -> Int {
            (Int(bytes[offset + 2]) * 77 + Int(bytes[offset + 1]) * 150 + Int(bytes[offset]) * 29) >> 8
        }

        for ty in 0..<outHeight {
            let y0 = ty * height / outHeight
            let y1 = max(y0 + 1, (ty + 1) * height / outHeight)
            let topRow = min(y0 + (y1 - y0) / 4, height - 1) * bytesPerRow
            let bottomRow = min(y0 + 3 * (y1 - y0) / 4, height - 1) * bytesPerRow
            let outRow = ty * outWidth
            for tx in 0..<outWidth {
                let left = leftColumns[tx], right = rightColumns[tx]
                let sum = luma(topRow + left) + luma(topRow + right) + luma(bottomRow + left) + luma(bottomRow + right)
                output[outRow + tx] = UInt8(sum / 4)
            }
        }
        return GrayscaleFrame(width: outWidth, height: outHeight, pixels: output)
    }
}
