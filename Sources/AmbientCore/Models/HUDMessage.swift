import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a HUD message came from (SPEC LA-51), shown on the card so
/// estimates by the on-device model are never mistaken for facts.
public enum IntelSource: String, Sendable, Codable {
    /// Deterministic rules (conversions, error hints, abbreviations defined on screen).
    case rule
    /// Apple's on-device ML (Vision, Translation).
    case onDeviceML
    /// The on-device language model (Foundation Models) — an estimate.
    case onDeviceLLM
    /// The user's own history (archive, earlier reading).
    case history
    /// The Mac's built-in dictionaries.
    case dictionary

    /// Card label (HUD chrome stays English).
    public var label: String {
        switch self {
        case .rule: return "SRC ▸ RULE"
        case .onDeviceML: return "SRC ▸ ON-DEVICE ML"
        case .onDeviceLLM: return "SRC ▸ ON-DEVICE AI · ESTIMATE"
        case .history: return "SRC ▸ YOUR HISTORY"
        case .dictionary: return "SRC ▸ DICTIONARY"
        }
    }
}

/// Content to show in the HUD. UI agnostic so it can be produced off the main thread.
public struct HUDMessage: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case translation
        /// A technical term explained (title = term, original = expansion, detail = explanation).
        case explanation
        /// An error on screen with likely causes (title = error kind, original = error line).
        case errorAnalysis
        /// What the code under the pointer does.
        case codeSummary
        /// Sensitive information visible while sharing the screen (no value shown).
        case securityWarning
        /// Where an on-screen QR code leads.
        case qrCode
        /// "Pick up where you left off" (title = session name).
        case resume
        /// An animal, plant, landmark, dish or product estimated on-device (title = name, original = scientific name / place).
        case identification
        /// A public figure named on screen (title = name, original = role).
        case publicFigure
        /// The film / series / anime being watched (title = work, original = kind · year · episode).
        case mediaInfo
        /// A character or performer of the current work named on screen.
        case cast
        /// Background of a news story (title = heading, original = headline).
        case newsContext
        /// Quantities converted to metric (title = first original, detail = "72°F → 22.2 °C" lines).
        case conversion
        /// What a circled area is about (on-device model; title = "TARGET", original = first line of the text).
        case regionSummary
        /// A circled area where nothing could be found (short feedback so the request isn't ignored silently).
        case noIntel
        /// The visible page condensed into up to three lines, on request (title = page, detail = lines).
        case screenSummary
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
    /// When the subject was last seen before (re-appearance notice), if ever.
    public let previouslySeen: Date?
    /// Set when it differs from the kind's usual source (e.g. a rule-based error hint).
    public let explicitSource: IntelSource?

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
        capturedAt: Date = Date(),
        previouslySeen: Date? = nil,
        source: IntelSource? = nil
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
        self.previouslySeen = previouslySeen
        self.explicitSource = source
    }

    /// What produced this message (nil for the "no intel" feedback).
    public var source: IntelSource? {
        if let explicitSource { return explicitSource }
        switch kind {
        case .translation, .qrCode: return .onDeviceML
        case .explanation, .errorAnalysis, .codeSummary, .identification, .publicFigure, .mediaInfo, .newsContext, .regionSummary,
             .screenSummary:
            return .onDeviceLLM
        case .securityWarning, .conversion, .cast: return .rule
        case .resume: return .history
        case .noIntel: return nil
        }
    }

    /// A copy with a re-appearance date attached.
    public func withPreviouslySeen(_ date: Date?) -> HUDMessage {
        HUDMessage(id: id, kind: kind, title: title, original: original, detail: detail, anchor: anchor,
                   features: features, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                   confidence: confidence, capturedAt: capturedAt, previouslySeen: date, source: explicitSource)
    }

    /// Display time is extended while a briefing is being generated.
    public func displayDuration(withBriefing: Bool) -> TimeInterval {
        withBriefing ? min(8, displayDuration + 2) : displayDuration
    }

    /// Display time between 3 and 6 seconds depending on how much there is to read
    /// ("no intel" feedback only briefly).
    public var displayDuration: TimeInterval {
        if kind == .noIntel { return 1.5 }
        let characters = Double(original.count + detail.count)
        return min(6, max(3, 3 + characters / 60))
    }

    /// Two messages are duplicates when they would show the same content.
    public func isDuplicate(of other: HUDMessage?) -> Bool {
        guard let other else { return false }
        return kind == other.kind && original == other.original && detail == other.detail
    }
}
