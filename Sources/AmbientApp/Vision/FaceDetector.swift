import CoreVideo
import Foundation
import Vision

/// Whether a face is visible in the regions — presence only. Faces are never
/// recognized, stored or sent anywhere.
final class FaceDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ambient.vision.faces", qos: .utility)

    func containsFace(in pixelBuffer: CVPixelBuffer, regions: [ChangedRegion]) async -> Bool {
        let pixelBox = PixelBufferBox(buffer: pixelBuffer)
        return await withCheckedContinuation { continuation in
            queue.async {
                for region in regions {
                    let request = VNDetectFaceRectanglesRequest()
                    request.regionOfInterest = FrameConverter.visionRect(fromTopLeft: region.rect)
                    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBox.buffer, options: [:])
                    if (try? handler.perform([request])) != nil, !(request.results ?? []).isEmpty {
                        continuation.resume(returning: true)
                        return
                    }
                }
                continuation.resume(returning: false)
            }
        }
    }
}
