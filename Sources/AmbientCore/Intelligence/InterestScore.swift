import Foundation

public enum InterestLevel: String, Sendable, Equatable {
    /// 0.0 ..< 0.5 — never shown.
    case ignore
    /// 0.5 ..< 0.7 — could be shown on demand (not shown in v0.1).
    case optional
    /// 0.7 ... 1.0 — shown in the HUD.
    case show
}

public struct InterestScore: Sendable, Equatable, Comparable {
    public static let optionalThreshold = 0.5
    public static let showThreshold = 0.7

    public let value: Double

    public init(_ value: Double) {
        self.value = value.isFinite ? min(max(value, 0), 1) : 0
    }

    public var level: InterestLevel {
        switch value {
        case InterestScore.showThreshold...: return .show
        case InterestScore.optionalThreshold...: return .optional
        default: return .ignore
        }
    }

    public static func < (lhs: InterestScore, rhs: InterestScore) -> Bool { lhs.value < rhs.value }
}
