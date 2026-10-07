import Foundation

/// Every user-switchable kind of intel. Settings turn each on or off, and
/// the ones that compete for the HUD are ranked by the user (SPEC ST-1/ST-2).
public enum IntelFeature: String, CaseIterable, Codable, Sendable, Identifiable {
    // Compete for the HUD (rankable).
    case qrCode
    case errorExplanation
    case translation
    case unitConversion
    case termExplanation
    case codeSummary
    case identification
    case publicFigure
    case castOnScreen
    case regionSummary
    // Supporting or page-level features (on/off only).
    case briefing
    case llmRouter
    case glossary
    case errorHints
    case mediaCard
    case newsBackground
    case sensitiveWarning
    case circleLookup
    case archiveQuestion
    case dictionary
    case screenSummary

    public var id: String { rawValue }

    /// Features that compete for the same HUD slot and can be reordered.
    public static let rankable: [IntelFeature] = [
        .qrCode, .errorExplanation, .translation, .unitConversion, .termExplanation,
        .codeSummary, .identification, .publicFigure, .castOnScreen, .regionSummary
    ]

    public var isRankable: Bool { Self.rankable.contains(self) }

    /// Needs the on-device LLM (Apple Intelligence) to do anything.
    public var requiresLanguageModel: Bool {
        switch self {
        case .codeSummary, .identification, .publicFigure, .regionSummary, .briefing, .llmRouter, .mediaCard, .archiveQuestion, .screenSummary:
            return true
        case .qrCode, .errorExplanation, .translation, .unitConversion, .termExplanation, .castOnScreen,
             .glossary, .errorHints, .newsBackground, .sensitiveWarning, .circleLookup, .dictionary:
            return false
        }
    }

    /// English UI label (localized in the app's string catalog).
    public var title: String {
        switch self {
        case .qrCode: return "QR codes"
        case .errorExplanation: return "Error causes (terminal, editor)"
        case .translation: return "Translation"
        case .unitConversion: return "Units, times, dates and cron (pointer rest)"
        case .termExplanation: return "Technical terms"
        case .codeSummary: return "What code does (pointer rest)"
        case .identification: return "Animals, plants, landmarks, dishes, products (estimate)"
        case .publicFigure: return "Public figures named on screen (estimate)"
        case .castOnScreen: return "Cast named in subtitles"
        case .regionSummary: return "“What is this?” for circled text"
        case .briefing: return "One-line briefing notes"
        case .llmRouter: return "AI judgment of borderline cards"
        case .glossary: return "Abbreviations defined on screen"
        case .errorHints: return "Rule-based error hints"
        case .mediaCard: return "Work card (movie, anime)"
        case .newsBackground: return "News background"
        case .sensitiveWarning: return "Warn about secrets while sharing"
        case .circleLookup: return "Circle with ⌥ to look up"
        case .archiveQuestion: return "Answer questions about the archive"
        case .dictionary: return "Dictionary definitions (macOS dictionaries)"
        case .screenSummary: return "Summarize the screen (⌥⌘S)"
        }
    }

    /// The feature behind a router action.
    public init?(action: SuggestedAction) {
        switch action {
        case .translate: self = .translation
        case .explainError: self = .errorExplanation
        case .explainTerm: self = .termExplanation
        case .explainCode: self = .codeSummary
        case .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyProduct: self = .identification
        case .identifyPerson: self = .publicFigure
        case .ignore: return nil
        }
    }
}

/// Which features are on and in what order the competing ones win.
public struct FeatureSettings: Codable, Equatable, Sendable {
    public var disabled: Set<IntelFeature>
    /// Rankable features, highest priority first.
    public private(set) var order: [IntelFeature]

    public init(disabled: Set<IntelFeature> = [], order: [IntelFeature] = IntelFeature.rankable) {
        self.disabled = disabled
        self.order = Self.normalized(order)
    }

    public static let `default` = FeatureSettings()

    public func isEnabled(_ feature: IntelFeature) -> Bool {
        !disabled.contains(feature)
    }

    public mutating func set(_ feature: IntelFeature, enabled: Bool) {
        if enabled { disabled.remove(feature) } else { disabled.insert(feature) }
    }

    /// 0 is the highest priority; non-rankable features rank last.
    public func rank(of feature: IntelFeature) -> Int {
        order.firstIndex(of: feature) ?? order.count
    }

    /// Moves a rankable feature one place up (toward higher priority) or down.
    public mutating func move(_ feature: IntelFeature, up: Bool) {
        guard let index = order.firstIndex(of: feature) else { return }
        let target = up ? index - 1 : index + 1
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    public mutating func resetOrder() {
        order = IntelFeature.rankable
    }

    /// `features` that are enabled, highest priority first (stable for equal ranks).
    public func ordered(_ features: [IntelFeature]) -> [IntelFeature] {
        features.enumerated()
            .filter { isEnabled($0.element) }
            .sorted { (rank(of: $0.element), $0.offset) < (rank(of: $1.element), $1.offset) }
            .map { $0.element }
    }

    /// Router candidates whose feature is enabled.
    public func enabledCandidates(_ candidates: [RoutedAction]) -> [RoutedAction] {
        candidates.filter { candidate in
            guard let feature = IntelFeature(action: candidate.action) else { return false }
            return isEnabled(feature)
        }
    }

    /// Among enabled candidates that reached the show threshold, the user's
    /// highest-priority feature wins; ties go to the more important candidate.
    public func select(from candidates: [RoutedAction]) -> RouterDecision {
        let enabled = enabledCandidates(candidates)
        let shown = enabled.filter { $0.interestScore.level == .show }
        let selected = shown.min { lhs, rhs in
            let left = IntelFeature(action: lhs.action).map(rank(of:)) ?? Int.max
            let right = IntelFeature(action: rhs.action).map(rank(of:)) ?? Int.max
            return left != right ? left < right : lhs.importance > rhs.importance
        } ?? .ignore
        return RouterDecision(selected: selected, candidates: enabled)
    }

    /// Keeps the user's order, drops duplicates and non-rankable entries, and
    /// appends rankable features missing from it (e.g. added in a later version).
    static func normalized(_ order: [IntelFeature]) -> [IntelFeature] {
        var seen = Set<IntelFeature>()
        var result = order.filter { $0.isRankable && seen.insert($0).inserted }
        result += IntelFeature.rankable.filter { !seen.contains($0) }
        return result
    }

    // Decoding normalizes too, so stored settings from older versions stay valid.
    private enum CodingKeys: String, CodingKey { case disabled, order }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let disabledRaw = try container.decodeIfPresent([String].self, forKey: .disabled) ?? []
        let orderRaw = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        self.init(disabled: Set(disabledRaw.compactMap(IntelFeature.init(rawValue:))),
                  order: orderRaw.compactMap(IntelFeature.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(disabled.map(\.rawValue).sorted(), forKey: .disabled)
        try container.encode(order.map(\.rawValue), forKey: .order)
    }
}
