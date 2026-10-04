import Foundation

/// Identity of a "page": the URL when known, otherwise app + window title.
public struct PageKey: Sendable, Hashable, Codable {
    public let value: String

    public init(bundleIdentifier: String?, windowTitle: String?, url: URL?) {
        if let url {
            value = "url:" + url.absoluteString
        } else {
            value = "win:\(bundleIdentifier ?? "?")|\(TextHeuristics.normalized(windowTitle ?? ""))"
        }
    }

    public init(rawValue: String) {
        value = rawValue
    }
}

/// What the user did while a page was in front.
public struct PageActivity: Sendable, Equatable {
    public var focusSeconds: TimeInterval = 0
    /// Earlier visits to the same page (e.g. in the last 7 days).
    public var revisits = 0
    /// Copy operations while the page was in front (pasteboard changes).
    public var copies = 0
    /// Times the pointer rested on the page for a while.
    public var pointerDwells = 0
    /// HUD intel shown on the page.
    public var intelShown = 0

    public init(focusSeconds: TimeInterval = 0, revisits: Int = 0, copies: Int = 0, pointerDwells: Int = 0, intelShown: Int = 0) {
        self.focusSeconds = focusSeconds
        self.revisits = revisits
        self.copies = copies
        self.pointerDwells = pointerDwells
        self.intelShown = intelShown
    }
}

public enum BookmarkReason: String, Sendable, Codable, CaseIterable {
    case longRead = "dwell"
    case revisited = "revisit"
    case copied = "copy"
    case pointerFocus = "pointer"
    case intel = "intel"
}

public struct BookmarkScore: Sendable, Equatable {
    public let value: Double
    public let reasons: [BookmarkReason]

    public init(value: Double, reasons: [BookmarkReason]) {
        self.value = min(max(value, 0), 1)
        self.reasons = reasons
    }

    public var isBookmark: Bool { value >= BookmarkScorer.threshold }
}

/// Estimates how important a page was from implicit signals
/// (spec: long reading, revisits, slow reading, pointer dwell, copying).
public enum BookmarkScorer {
    public static let threshold = 0.6

    public static func score(_ activity: PageActivity) -> BookmarkScore {
        var value = 0.0
        var reasons: [BookmarkReason] = []
        // Reading time: saturates at 5 minutes; under 30 s counts for nothing.
        let read = min(1, max(0, (activity.focusSeconds - 30) / 270))
        if read > 0 {
            value += 0.4 * read
            if read >= 0.5 { reasons.append(.longRead) }
        }
        if activity.revisits > 0 {
            value += min(0.3, 0.12 * Double(activity.revisits))
            if activity.revisits >= 2 { reasons.append(.revisited) }
        }
        if activity.copies > 0 {
            value += min(0.35, 0.25 + 0.05 * Double(activity.copies - 1))
            reasons.append(.copied)
        }
        if activity.pointerDwells > 0 {
            value += min(0.15, 0.05 * Double(activity.pointerDwells))
            if activity.pointerDwells >= 2 { reasons.append(.pointerFocus) }
        }
        if activity.intelShown > 0 {
            value += min(0.1, 0.05 * Double(activity.intelShown))
            reasons.append(.intel)
        }
        return BookmarkScore(value: min(1, value), reasons: reasons)
    }
}
