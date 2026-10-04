import Foundation

/// Cloud identification (Gemini in the app). Images are cropped regions only.
public protocol CloudIdentifying: Sendable {
    var isAvailable: Bool { get }
    func identify(imageJPEG: Data, hint: VisualCategory, context: String, targetLanguage: String) async throws -> IdentificationAnswer
    func publicFigure(named name: String, context: String, targetLanguage: String) async throws -> PublicFigureAnswer
}

public enum IdentificationPolicy {
    /// Below this, nothing is shown.
    public static let minimumConfidence = 0.55
    /// Below this, the name is hedged ("…の可能性があります").
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

    /// "カワセミ" or "カワセミ（の可能性があります）" / "Kingfisher (possibly)".
    public static func displayName(_ name: String, confidence: Double, language: String) -> String {
        guard confidence < assertiveConfidence else { return name }
        return LanguageCode.base(language) == "ja" ? "\(name)（の可能性があります）" : "\(name) (possibly)"
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
