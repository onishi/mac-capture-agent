import Foundation

/// What to show for an area the user circled (SPEC LA-60). The user
/// asked explicitly, so the ignore-first threshold and cooldowns do not apply;
/// the most specific thing found wins.
public enum ActiveLookupPlan: Sendable, Equatable {
    case qrCode(String)
    case explainError(RoutedAction)
    case translate(RoutedAction)
    case convertUnits([UnitConversion])
    case explainTerm(RoutedAction)
    case explainCode(String)
    case identify(VisualCategory)
    /// Ask the on-device model what the text is about.
    case describe(String)
    case nothing
}

public enum ActiveLookupPlanner {
    /// Text shorter than this is not worth describing.
    public static let minimumDescribeLength = 12

    /// Collects what the circled area could be answered with, then picks the
    /// user's highest-priority enabled feature (default order: QR → error →
    /// foreign text → units → term → code → picture → description).
    /// `candidates` are the router's candidates for the circled area (any score).
    public static func plan(
        qrPayloads: [String],
        candidates: [RoutedAction],
        text: String,
        conversions: [UnitConversion],
        categories: [VisualCategory],
        canUseLanguageModel: Bool,
        features: FeatureSettings = .default
    ) -> ActiveLookupPlan {
        let options = eligible(qrPayloads: qrPayloads, candidates: candidates, text: text, conversions: conversions,
                               categories: categories, canUseLanguageModel: canUseLanguageModel)
        let order = features.ordered(options.map { $0.feature })
        guard let best = order.first, let option = options.first(where: { $0.feature == best }) else { return .nothing }
        return option.plan
    }

    /// Every answer that fits the circled area, in the default order.
    static func eligible(
        qrPayloads: [String],
        candidates: [RoutedAction],
        text: String,
        conversions: [UnitConversion],
        categories: [VisualCategory],
        canUseLanguageModel: Bool
    ) -> [(feature: IntelFeature, plan: ActiveLookupPlan)] {
        var options: [(feature: IntelFeature, plan: ActiveLookupPlan)] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = qrPayloads.first { options.append((.qrCode, .qrCode(code))) }
        if let error = candidates.first(where: { $0.action == .explainError }) { options.append((.errorExplanation, .explainError(error))) }
        // A short quantity ("72°F", "5 miles away") is about the unit, not the language.
        let isShortQuantity = !conversions.isEmpty && trimmed.count < 40
        if !isShortQuantity, let foreign = candidates.first(where: { $0.action == .translate }) {
            options.append((.translation, .translate(foreign)))
        }
        if !conversions.isEmpty { options.append((.unitConversion, .convertUnits(conversions))) }
        // A term circled on its own; inside a longer text the user more likely wants the gist
        // (without the model, the glossary may still know the term).
        if let term = candidates.first(where: { $0.action == .explainTerm }), let payload = term.payload,
           trimmed.count <= payload.count + 40 || !canUseLanguageModel {
            options.append((.termExplanation, .explainTerm(term)))
        }
        if canUseLanguageModel, trimmed.count >= 40, DeveloperOutputSanitizer.looksLikeCode(trimmed) {
            options.append((.codeSummary, .explainCode(trimmed)))
        }
        // Mostly picture: little text, and the classifier saw something nameable.
        if let category = categories.first(where: { [.animal, .plant, .landmark, .food, .product].contains($0) }),
           trimmed.count < 80 {
            options.append((.identification, .identify(category)))
        }
        if canUseLanguageModel, trimmed.count >= minimumDescribeLength {
            options.append((.regionSummary, .describe(trimmed)))
        }
        return options
    }
}

/// "What is this?" for circled text, on-device (Foundation Models in the app).
public protocol RegionDescribing: Sendable {
    var isAvailable: Bool { get }
    func describe(text: String, appName: String?, targetLanguage: String) async throws -> String
}

public enum RegionDescription {
    public static let maximumInputLength = 800
    public static let maximumLength = 160

    public static func instructions(targetLanguage: String) -> String {
        """
        The user circled part of their screen and wants to know what it is. You get the text inside the circle. \
        In one or two short sentences say what it is or what it means for the user (summarize, explain or clarify). \
        Do not repeat the text. Do not invent facts that are not implied by the text. If it is meaningless UI chrome, \
        say so briefly. Answer in the language with code "\(targetLanguage)".
        """
    }

    /// Cleans the model's answer; nil when it is empty or just repeats the input.
    public static func sanitize(_ answer: String, input: String) -> String? {
        let collapsed = TextHeuristics.normalized(answer.replacingOccurrences(of: "\n", with: " "))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”「」*` "))
        guard !collapsed.isEmpty, EntityName.canonical(collapsed) != EntityName.canonical(input) else { return nil }
        return collapsed.count > maximumLength ? String(collapsed.prefix(maximumLength - 1)) + "…" : collapsed
    }
}
