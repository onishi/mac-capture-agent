import CoreVideo
import Foundation
import Vision

/// Text recognition with `VNRecognizeTextRequest`, limited to changed regions.
///
/// Vision calls are synchronous, so they run on a dedicated serial queue
/// instead of blocking Swift Concurrency's cooperative thread pool.
final class OCRService: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ambient.vision.ocr", qos: .utility)
    /// Regions smaller than this (normalized area) are skipped.
    private let minimumRegionArea: CGFloat = 0.0005

    func recognizeText(in pixelBuffer: CVPixelBuffer, regions: [ChangedRegion]) async -> [RecognizedTextRegion] {
        let pixelBox = PixelBufferBox(buffer: pixelBuffer)
        return await withCheckedContinuation { continuation in
            queue.async {
                let results = regions
                    .filter { $0.area >= self.minimumRegionArea }
                    .flatMap { self.recognize(in: pixelBox.buffer, region: $0) }
                continuation.resume(returning: results)
            }
        }
    }

    /// QR codes in the regions: payload and normalized top-left rect.
    func detectQRCodes(in pixelBuffer: CVPixelBuffer, regions: [ChangedRegion]) async -> [(payload: String, rect: CGRect)] {
        let pixelBox = PixelBufferBox(buffer: pixelBuffer)
        return await withCheckedContinuation { continuation in
            queue.async {
                var codes: [(payload: String, rect: CGRect)] = []
                for region in regions where region.area >= self.minimumRegionArea {
                    let roi = FrameConverter.visionRect(fromTopLeft: region.rect)
                    let request = VNDetectBarcodesRequest()
                    request.symbologies = [.qr]
                    request.regionOfInterest = roi
                    let handler = VNImageRequestHandler(cvPixelBuffer: pixelBox.buffer, options: [:])
                    do {
                        try handler.perform([request])
                    } catch {
                        continue
                    }
                    for observation in request.results ?? [] {
                        guard let payload = observation.payloadStringValue else { continue }
                        codes.append((payload, FrameConverter.topLeftRect(fromVisionBox: observation.boundingBox, regionOfInterest: roi)))
                    }
                }
                continuation.resume(returning: codes)
            }
        }
    }

    private func recognize(in pixelBuffer: CVPixelBuffer, region: ChangedRegion) -> [RecognizedTextRegion] {
        let roi = FrameConverter.visionRect(fromTopLeft: region.rect)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.regionOfInterest = roi

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.vision.error("OCR failed: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedTextRegion(
                text: candidate.string,
                boundingBox: FrameConverter.topLeftRect(fromVisionBox: observation.boundingBox, regionOfInterest: roi),
                confidence: candidate.confidence
            )
        }
    }
}

/// Lets a `CVPixelBuffer` cross into the Vision queue. The buffer is only read.
struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}
