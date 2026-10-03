import Foundation

/// A piece of text recognized by OCR.
///
/// `boundingBox` is normalized to the whole captured display with a top-left origin.
public struct RecognizedTextRegion: Sendable, Equatable {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float

    public init(text: String, boundingBox: CGRect, confidence: Float) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}
