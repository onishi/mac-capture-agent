import Foundation

/// On-device identification (Foundation Models in the app). The local model
/// reads text only: Vision's classification labels and the words near the
/// image stand in for the picture, so answers are estimates (LOCAL_AI.md §2.1).
public protocol VisualIdentifying: Sendable {
    var isAvailable: Bool { get }
    func identify(labels: [VisualLabel], hint: VisualCategory, context: String, targetLanguage: String) async throws -> IdentificationAnswer
    func publicFigure(named name: String, context: String, targetLanguage: String) async throws -> PublicFigureAnswer
}

/// What the local model makes of the classification labels and nearby text.
public struct IdentificationAnswer: Codable, Sendable, Equatable {
    public var category: String          // "animal" | "plant" | "landmark" | "food" | "product" | "none"
    public var name: String              // common name in the user's language
    public var scientificName: String    // or location for landmarks; may be empty
    public var facts: [String]           // up to 3 short facts
    public var confidence: Double        // 0...1

    public init(category: String, name: String, scientificName: String, facts: [String], confidence: Double) {
        self.category = category
        self.name = name
        self.scientificName = scientificName
        self.facts = facts
        self.confidence = confidence
    }

    public static func instructions(targetLanguage: String) -> String {
        """
        You cannot see the image. You get labels from an on-device image classifier (with scores) and the text \
        printed near the image, such as a caption. Name the main animal, plant, landmark, dish (food) or product. \
        Never identify or describe people. Prefer a name that appears in the nearby text. If the labels are too \
        generic and the text does not name it, answer with the most specific safe name (e.g. "bird") or category "none". \
        For animals and plants give the common name and the scientific name; for landmarks the name and its \
        city/country in scientificName; for food the dish and its cuisine; for products the product and the brand. \
        At most 3 short facts. Never invent facts you are unsure of. \
        Answer in the language with code "\(targetLanguage)" (scientific names stay in Latin).
        """
    }

    public static func prompt(labels: [VisualLabel], hint: VisualCategory, context: String) -> String {
        let labelLine = labels.map { "\($0.identifier) (\(String(format: "%.2f", $0.confidence)))" }.joined(separator: ", ")
        return """
            Expected subject: \(hint.rawValue)
            Classifier labels: \(labelLine)
            Nearby text: \(String(context.prefix(200)))
            """
    }
}

/// Whether a person *named on screen* is a public figure, and who they are.
public struct PublicFigureAnswer: Codable, Sendable, Equatable {
    public var isPublicFigure: Bool
    public var name: String
    public var role: String
    public var knownFor: [String]
    public var confidence: Double

    public init(isPublicFigure: Bool, name: String, role: String, knownFor: [String], confidence: Double) {
        self.isPublicFigure = isPublicFigure
        self.name = name
        self.role = role
        self.knownFor = knownFor
        self.confidence = confidence
    }

    public static func instructions(targetLanguage: String) -> String {
        """
        A name appears on the user's screen (caption, subtitle, title). Decide whether it refers to a widely known \
        public figure (actor, musician, athlete, politician, executive, author…) and, if so, who. \
        Use only well-established public information you are sure of. If the person is a private individual, \
        not clearly identifiable from the name and context, or you are unsure, set isPublicFigure to false and \
        leave other fields empty. Never guess. role: one short phrase. knownFor: up to 3 works or achievements. \
        Answer in the language with code "\(targetLanguage)" (keep proper names as commonly written).
        """
    }
}

public enum IdentificationPolicy {
    /// Below this, nothing is shown.
    public static let minimumConfidence = 0.55
    /// Below this, the name is hedged ("…かもしれません").
    public static let assertiveConfidence = 0.8
    /// Public figures need a higher bar.
    public static let publicFigureConfidence = 0.75
    /// Image regions smaller than this (normalized area) are not worth identifying.
    public static let minimumRegionArea = 0.08

    public static func accept(_ answer: IdentificationAnswer, hint: VisualCategory) -> Bool {
        guard answer.category != "none", answer.confidence >= minimumConfidence,
              !answer.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return answer.category == hint.rawValue || hint == .unknown
    }

    public static func accept(_ answer: PublicFigureAnswer, nameOnScreen: String) -> Bool {
        guard answer.isPublicFigure, answer.confidence >= publicFigureConfidence,
              !answer.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        // The answer must be about the name that is actually on screen.
        let onScreen = EntityName.canonical(nameOnScreen)
        let answered = EntityName.canonical(answer.name)
        return answered.contains(onScreen) || onScreen.contains(answered)
            || !Set(onScreen.split(separator: " ")).isDisjoint(with: Set(answered.split(separator: " ")))
    }

    /// The local model has no picture, so its own confidence is not trusted:
    /// a name is stated plainly only when the screen text corroborates it,
    /// otherwise the score is capped below the assertive level (hedged).
    public static func localConfidence(_ answer: IdentificationAnswer, labelConfidence: Double, nearbyText: String) -> Double {
        let model = min(max(answer.confidence, 0), 1)
        if isCorroborated(answer, by: nearbyText) {
            return max(model, assertiveConfidence)
        }
        // Uncorroborated: as sure as the classifier at best, never assertive.
        return min(model, labelConfidence, assertiveConfidence - 0.01)
    }

    /// The answer's name (or scientific name) is printed near the image.
    public static func isCorroborated(_ answer: IdentificationAnswer, by text: String) -> Bool {
        let haystack = EntityName.canonical(text)
        return [answer.name, answer.scientificName].contains { name in
            let needle = EntityName.canonical(name)
            let long = needle.count >= 3 || (needle.count >= 2 && needle.unicodeScalars.contains(where: TextHeuristics.isCJK))
            return long && haystack.contains(needle)
        }
    }

    /// "カワセミ" or "カワセミ（かもしれません）" / "Kingfisher (possibly)".
    public static func displayName(_ name: String, confidence: Double, language: String) -> String {
        guard confidence < assertiveConfidence else { return name }
        return LanguageCode.base(language) == "ja" ? "\(name)（かもしれません）" : "\(name) (possibly)"
    }

    /// Searches opened in the browser from the HUD (no network use by the app).
    public static func webSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    public static func wikipediaURL(for title: String, language: String) -> URL? {
        let base = LanguageCode.base(language)
        let lang = base.allSatisfy(\.isLetter) && (2...3).contains(base.count) ? base : "en"
        var components = URLComponents(string: "https://\(lang).wikipedia.org/wiki/Special:Search")
        components?.queryItems = [URLQueryItem(name: "search", value: title)]
        return components?.url
    }
}
