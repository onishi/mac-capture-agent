import Foundation

/// User reactions used to tune what gets shown.
public enum PersonalizationFeedback: String, Sendable, Equatable, Codable {
    /// HUD dismissed right away / marked as not useful → score −
    case dismissedQuickly
    /// User looked at the details (hovered the HUD) → score +
    case openedDetails
    /// User searched for the item → score ++
    case searched

    var delta: Double {
        switch self {
        case .dismissedQuickly: return -0.08
        case .openedDetails: return 0.03
        case .searched: return 0.08
        }
    }
}

/// The non-content features a candidate is personalized on. Deliberately
/// coarse: no text is ever stored, only action, language and app.
public struct PersonalizationFeatures: Sendable, Equatable, Hashable, Codable {
    public let action: SuggestedAction
    public let language: String?
    public let bundleIdentifier: String?

    public init(action: SuggestedAction, language: String?, bundleIdentifier: String?) {
        self.action = action
        self.language = language.map(LanguageCode.base)
        self.bundleIdentifier = bundleIdentifier
    }

    /// Keys whose weights apply to these features, with how strongly feedback
    /// generalizes to them: rejecting French mostly affects French, a little
    /// the current app, and only slightly translations in general.
    var keys: [(key: String, scale: Double)] {
        var keys = [(key: "action:\(action.rawValue)", scale: 0.25)]
        if let language { keys.append((key: "action:\(action.rawValue)|lang:\(language)", scale: 1.0)) }
        if let bundleIdentifier { keys.append((key: "action:\(action.rawValue)|app:\(bundleIdentifier)", scale: 0.5)) }
        return keys
    }
}

/// Adjusts interest scores based on what the user has found useful before.
public protocol InterestAdjusting: Sendable {
    func adjust(_ score: InterestScore, features: PersonalizationFeatures) -> InterestScore
}

/// No personalization.
public struct NoPersonalization: InterestAdjusting {
    public init() {}
    public func adjust(_ score: InterestScore, features: PersonalizationFeatures) -> InterestScore {
        score
    }
}

/// Additive per-feature weights learned from feedback. Value type, Codable,
/// contains no screen content.
public struct PersonalizationModel: Sendable, Equatable, Codable {
    /// Maximum absolute weight of a single key.
    public static let maximumWeight = 0.3

    public private(set) var weights: [String: Double] = [:]

    public init() {}

    public mutating func record(_ feedback: PersonalizationFeedback, for features: PersonalizationFeatures) {
        for (key, scale) in features.keys {
            let updated = (weights[key] ?? 0) + feedback.delta * scale
            weights[key] = min(Self.maximumWeight, max(-Self.maximumWeight, updated))
        }
    }

    public func adjustment(for features: PersonalizationFeatures) -> Double {
        let total = features.keys.reduce(0) { $0 + (weights[$1.key] ?? 0) }
        return min(Self.maximumWeight, max(-Self.maximumWeight, total))
    }

    public mutating func reset() {
        weights.removeAll()
    }
}

/// Thread-safe `InterestAdjusting` backed by a `PersonalizationModel`.
/// Shared between the analysis pipeline (reads) and the UI (feedback).
public final class PersonalizationStore: InterestAdjusting, @unchecked Sendable {
    private let lock = NSLock()
    private var model: PersonalizationModel
    private let onChange: (@Sendable (PersonalizationModel) -> Void)?

    public init(model: PersonalizationModel = PersonalizationModel(), onChange: (@Sendable (PersonalizationModel) -> Void)? = nil) {
        self.model = model
        self.onChange = onChange
    }

    public var snapshot: PersonalizationModel {
        lock.lock(); defer { lock.unlock() }
        return model
    }

    public func record(_ feedback: PersonalizationFeedback, for features: PersonalizationFeatures) {
        lock.lock()
        model.record(feedback, for: features)
        let updated = model
        lock.unlock()
        onChange?(updated)
    }

    public func reset() {
        lock.lock()
        model.reset()
        let updated = model
        lock.unlock()
        onChange?(updated)
    }

    public func adjust(_ score: InterestScore, features: PersonalizationFeatures) -> InterestScore {
        InterestScore(score.value + snapshot.adjustment(for: features))
    }
}
