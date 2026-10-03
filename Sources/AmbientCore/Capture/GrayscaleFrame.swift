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

        for ty in 0..<outHeight {
            let y0 = ty * height / outHeight
            let y1 = max(y0 + 1, (ty + 1) * height / outHeight)
            let sampleYs = (y0 + (y1 - y0) / 4, y0 + 3 * (y1 - y0) / 4)
            for tx in 0..<outWidth {
                let x0 = tx * width / outWidth
                let x1 = max(x0 + 1, (tx + 1) * width / outWidth)
                let sampleXs = (x0 + (x1 - x0) / 4, x0 + 3 * (x1 - x0) / 4)
                var sum = 0
                for sy in [sampleYs.0, sampleYs.1] {
                    let row = min(sy, height - 1) * bytesPerRow
                    for sx in [sampleXs.0, sampleXs.1] {
                        let offset = row + min(sx, width - 1) * 4
                        let b = Int(bytes[offset])
                        let g = Int(bytes[offset + 1])
                        let r = Int(bytes[offset + 2])
                        sum += (r * 77 + g * 150 + b * 29) >> 8
                    }
                }
                output[ty * outWidth + tx] = UInt8(sum / 4)
            }
        }
        return GrayscaleFrame(width: outWidth, height: outHeight, pixels: output)
    }
}
