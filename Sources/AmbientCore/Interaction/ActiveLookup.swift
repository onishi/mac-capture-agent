import Foundation

/// What to show for an area the user circled (LOCAL_AI.md LA-60). The user
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

    /// Order: QR → error → (short quantity) → foreign text → units → term → code → picture → description.
    /// `candidates` are the router's candidates for the circled area (any score).
    public static func plan(
        qrPayloads: [String],
        candidates: [RoutedAction],
        text: String,
        conversions: [UnitConversion],
        categories: [VisualCategory],
        canUseLanguageModel: Bool
    ) -> ActiveLookupPlan {
        if let code = qrPayloads.first { return .qrCode(code) }
        if let error = candidates.first(where: { $0.action == .explainError }) { return .explainError(error) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A short quantity ("72°F", "5 miles away") is about the unit, not the language.
        if !conversions.isEmpty, trimmed.count < 40 { return .convertUnits(conversions) }
        if let foreign = candidates.first(where: { $0.action == .translate }) { return .translate(foreign) }
        if !conversions.isEmpty { return .convertUnits(conversions) }

        let term = candidates.first(where: { $0.action == .explainTerm })
        // A term circled on its own; inside a longer text the user more likely wants the gist.
        if let term, let payload = term.payload, trimmed.count <= payload.count + 40 {
            return .explainTerm(term)
        }
        if canUseLanguageModel, trimmed.count >= 40, DeveloperOutputSanitizer.looksLikeCode(trimmed) {
            return .explainCode(trimmed)
        }
        // Mostly picture: little text, and the classifier saw something nameable.
        if let category = categories.first(where: { [.animal, .plant, .landmark, .food, .product].contains($0) }),
           trimmed.count < 80 {
            return .identify(category)
        }
        if canUseLanguageModel, trimmed.count >= minimumDescribeLength {
            return .describe(trimmed)
        }
        if let term { return .explainTerm(term) }   // the glossary may still know it
        return .nothing
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
