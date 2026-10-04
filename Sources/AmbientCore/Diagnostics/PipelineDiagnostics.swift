import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What the pipeline did on one analysis pass, for the debug overlay.
/// Never contains recognized text — only geometry, scores and timings.
public struct PipelineDiagnostics: Sendable, Equatable {
    public struct Candidate: Sendable, Equatable {
        public let action: SuggestedAction
        public let importance: Double
        public let region: CGRect?
        public let selected: Bool
        public let suppressedByCooldown: Bool

        public init(action: SuggestedAction, importance: Double, region: CGRect?, selected: Bool, suppressedByCooldown: Bool = false) {
            self.action = action
            self.importance = importance
            self.region = region
            self.selected = selected
            self.suppressedByCooldown = suppressedByCooldown
        }

        /// e.g. "TRANSLATE 0.82 ✓", "TRANSLATE 0.61", "TRANSLATE 0.91 COOLDOWN"
        public var label: String {
            var text = "\(action.rawValue.uppercased()) \(String(format: "%.2f", importance))"
            if suppressedByCooldown {
                text += " COOLDOWN"
            } else if selected {
                text += " ✓"
            }
            return text
        }
    }

    /// Normalized, top-left-origin rects.
    public var changedRegions: [CGRect] = []
    public var analyzedRegions: [CGRect] = []
    public var textLineCount = 0
    public var textBlockCount = 0
    public var candidates: [Candidate] = []
    /// Stage name → milliseconds.
    public var timings: [String: Double] = [:]

    public init() {}

    public var hasAnalysis: Bool { !analyzedRegions.isEmpty }
}

/// Running totals since the pipeline started, shown in the debug overlay and
/// used for the on-device checklist ("unwanted HUDs per 30 minutes").
public struct PipelineCounters: Sendable, Equatable {
    public var framesChecked = 0
    public var changesDetected = 0
    public var analyses = 0
    public var hudsShown = 0
    public var suppressedByCooldown = 0
    public var ignored = 0
    public var failures = 0

    public init() {}

    public var summary: String {
        "FRAMES \(framesChecked) · CHANGES \(changesDetected) · OCR \(analyses) · HUD \(hudsShown) · COOLDOWN \(suppressedByCooldown) · IGNORED \(ignored) · FAIL \(failures)"
    }

    /// e.g. "DETECT 2ms · OCR 140ms · TRANSLATE 80ms" in a stable order.
    public static func formatTimings(_ timings: [String: Double]) -> String {
        let order = ["detect", "ocr", "classify", "route", "translate"]
        let known = order.compactMap { key in timings[key].map { "\(key.uppercased()) \(Int($0.rounded()))ms" } }
        let others = timings.keys.filter { !order.contains($0) }.sorted().compactMap { key in
            timings[key].map { "\(key.uppercased()) \(Int($0.rounded()))ms" }
        }
        return (known + others).joined(separator: " · ")
    }
}
