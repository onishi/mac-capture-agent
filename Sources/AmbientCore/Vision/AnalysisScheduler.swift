import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct AnalysisSchedulerConfiguration: Sendable, Equatable {
    /// Minimum time between two OCR passes (OCR runs at most at 1 / interval fps).
    public var minimumAnalysisInterval: TimeInterval = 1.0
    /// Pending changes are analyzed after this long even if the screen keeps changing.
    public var maximumPendingAge: TimeInterval = 2.0
    /// At most this many regions are analyzed per pass (largest first).
    public var maximumRegions: Int = 4
    /// Regions closer than this (normalized) are merged before analysis.
    public var mergeDistance: CGFloat = 0.02
    /// When the union of regions covers more than this, the whole screen is analyzed once.
    public var fullScreenCoverage: CGFloat = 0.5

    public init() {}
}

/// Decides *when* changed regions are worth analyzing.
///
/// Changes are accumulated until the screen settles (a tick without new
/// changes) or until they have been pending for too long, and analysis is
/// rate-limited so OCR never runs more often than configured.
public struct AnalysisScheduler: Sendable {
    public var configuration: AnalysisSchedulerConfiguration
    public private(set) var pending: [ChangedRegion] = []
    private var pendingSince: TimeInterval?
    private var lastAnalysis: TimeInterval?

    public init(configuration: AnalysisSchedulerConfiguration = AnalysisSchedulerConfiguration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        pending = []
        pendingSince = nil
    }

    /// Feeds the result of one change-detection tick.
    /// - Returns: the regions to analyze now, or `nil` when nothing should run.
    public mutating func ingest(_ regions: [ChangedRegion], at time: TimeInterval) -> [ChangedRegion]? {
        let stillChanging = !regions.isEmpty
        if stillChanging {
            pending = RegionMerger.merge(pending + regions, within: configuration.mergeDistance)
            if pendingSince == nil { pendingSince = time }
        }
        guard !pending.isEmpty, let since = pendingSince else { return nil }

        let settled = !stillChanging
        let tooOld = time - since >= configuration.maximumPendingAge
        let intervalElapsed = lastAnalysis.map { time - $0 >= configuration.minimumAnalysisInterval } ?? true
        guard (settled || tooOld) && intervalElapsed else { return nil }

        let result = selectRegions(pending)
        pending = []
        pendingSince = nil
        lastAnalysis = time
        return result
    }

    private func selectRegions(_ regions: [ChangedRegion]) -> [ChangedRegion] {
        let coverage = regions.reduce(CGFloat(0)) { $0 + $1.area }
        if coverage >= configuration.fullScreenCoverage {
            return [ChangedRegion(rect: .unit, confidence: regions.map(\.confidence).max() ?? 1)]
        }
        return Array(regions.sorted { $0.area > $1.area }.prefix(configuration.maximumRegions))
    }
}
