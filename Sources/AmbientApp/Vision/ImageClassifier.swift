import CoreVideo
import Foundation
import Vision

/// Result of one classification: coarse categories for the router and the
/// raw labels for on-device identification (SPEC LA-1).
struct ImageClassification: Sendable {
    var categories: [VisualCategory] = []
    var labels: [VisualLabel] = []
}

/// Coarse scene classification with Vision's built-in taxonomy
/// (`VNClassifyImageRequest`), mapped to `VisualCategory`.
final class ImageClassifier: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ambient.vision.classify", qos: .utility)

    func classify(_ pixelBuffer: CVPixelBuffer, region: CGRect) async -> ImageClassification {
        let pixelBox = PixelBufferBox(buffer: pixelBuffer)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.classifySync(pixelBox.buffer, region: region))
            }
        }
    }

    private func classifySync(_ pixelBuffer: CVPixelBuffer, region: CGRect) -> ImageClassification {
        let request = VNClassifyImageRequest()
        request.regionOfInterest = FrameConverter.visionRect(fromTopLeft: region)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.vision.error("Classification failed: \(error.localizedDescription, privacy: .public)")
            return ImageClassification()
        }
        let top = Array((request.results ?? []).prefix(10))
        let categories = VisualCategoryMapper.categories(for: top.map { (label: $0.identifier, confidence: $0.confidence) })
        let labels = top.map { VisualLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }
        return ImageClassification(categories: categories, labels: labels)
    }
}
