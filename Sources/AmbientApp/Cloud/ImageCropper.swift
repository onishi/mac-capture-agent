import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// JPEG of a screen region, downscaled, for cloud identification. Kept in memory only.
enum ImageCropper {
    private static let context = CIContext()

    /// - Parameter region: normalized, top-left-origin rect.
    static func jpeg(from pixelBuffer: CVPixelBuffer, region: CGRect, maxDimension: CGFloat = 768) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        let rect = CGRect(
            x: region.minX * extent.width,
            y: (1 - region.maxY) * extent.height,
            width: region.width * extent.width,
            height: region.height * extent.height
        ).integral.intersection(extent)
        guard rect.width >= 32, rect.height >= 32, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var cropped = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let scale = min(1, maxDimension / max(rect.width, rect.height))
        if scale < 1 {
            cropped = cropped.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return context.jpegRepresentation(of: cropped, colorSpace: colorSpace, options: [quality: 0.7])
    }
}
