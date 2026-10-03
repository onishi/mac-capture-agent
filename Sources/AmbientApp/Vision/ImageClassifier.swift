import CoreVideo
import Foundation
import Vision

/// Coarse scene classification with Vision's built-in taxonomy
/// (`VNClassifyImageRequest`), mapped to `VisualCategory`.
final class ImageClassifier: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ambient.vision.classify", qos: .utility)

    func classify(_ pixelBuffer: CVPixelBuffer, region: CGRect) async -> [VisualCategory] {
        let pixelBox = PixelBufferBox(buffer: pixelBuffer)
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.classifySync(pixelBox.buffer, region: region))
            }
        }
    }

    private func classifySync(_ pixelBuffer: CVPixelBuffer, region: CGRect) -> [VisualCategory] {
        let request = VNClassifyImageRequest()
        request.regionOfInterest = FrameConverter.visionRect(fromTopLeft: region)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.vision.error("Classification failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        let labels = (request.results ?? [])
            .prefix(10)
            .map { (label: $0.identifier, confidence: $0.confidence) }
        return VisualCategoryMapper.categories(for: Array(labels))
    }
}
