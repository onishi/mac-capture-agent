import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Content to show in the HUD. UI agnostic so it can be produced off the main thread.
public struct HUDMessage: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case translation
    }

    public let id: UUID
    public let kind: Kind
    public let title: String
    public let original: String
    public let detail: String
    /// Normalized, top-left-origin rect of the source on screen.
    public let anchor: CGRect?
    /// What the message is about, for personalization feedback (no text).
    public let features: PersonalizationFeatures?
    /// Source / target language codes, e.g. "fr" → "ja".
    public let sourceLanguage: String?
    public let targetLanguage: String?
    /// Detection confidence (0...1), shown as a meter.
    public let confidence: Double?
    public let capturedAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        original: String,
        detail: String,
        anchor: CGRect?,
        features: PersonalizationFeatures? = nil,
        sourceLanguage: String? = nil,
        targetLanguage: String? = nil,
        confidence: Double? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.original = original
        self.detail = detail
        self.anchor = anchor
        self.features = features
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.capturedAt = capturedAt
    }

    /// Display time is extended while a briefing is being generated.
    public func displayDuration(withBriefing: Bool) -> TimeInterval {
        withBriefing ? min(8, displayDuration + 2) : displayDuration
    }

    /// Display time between 3 and 6 seconds depending on how much there is to read.
    public var displayDuration: TimeInterval {
        let characters = Double(original.count + detail.count)
        return min(6, max(3, 3 + characters / 60))
    }

    /// Two messages are duplicates when they would show the same content.
    public func isDuplicate(of other: HUDMessage?) -> Bool {
        guard let other else { return false }
        return kind == other.kind && original == other.original && detail == other.detail
    }
}
