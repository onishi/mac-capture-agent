import Foundation

/// What a briefing is generated from. Only the text already shown in the HUD
/// plus coarse context; never the screenshot.
public struct BriefingRequest: Sendable, Equatable {
    public let original: String
    public let translation: String
    public let sourceLanguage: String?
    public let targetLanguage: String
    public let appName: String?

    public init(original: String, translation: String, sourceLanguage: String?, targetLanguage: String, appName: String?) {
        self.original = original
        self.translation = translation
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.appName = appName
    }
}

/// Generates a one-line contextual note ("BRIEF") for a HUD message.
/// Implemented with Apple's on-device Foundation Models in the app.
public protocol BriefingProvider: Sendable {
    var isAvailable: Bool { get }
    func briefing(for request: BriefingRequest) async throws -> String
}

public enum BriefingPrompt {
    public static let maximumInputLength = 500

    public static func instructions(targetLanguage: String) -> String {
        """
        You add one short, useful note to a translation the user is reading on screen. \
        Explain the context or implication in plain words: what kind of text it is, \
        what it means for the reader, or a cultural nuance. Do not repeat the translation. \
        Do not speculate about people. Answer with a single sentence of at most 40 characters \
        in the language with code "\(targetLanguage)". If there is nothing useful to add, answer "-".
        """
    }

    public static func prompt(for request: BriefingRequest) -> String {
        let original = String(request.original.prefix(maximumInputLength))
        let translation = String(request.translation.prefix(maximumInputLength))
        var lines = [
            "Original (\(request.sourceLanguage ?? "unknown")): \(original)",
            "Translation (\(request.targetLanguage)): \(translation)"
        ]
        if let app = request.appName, !app.isEmpty {
            lines.append("Seen in app: \(app)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Cleans model output and rejects anything that isn't a short useful note.
public enum BriefingSanitizer {
    public static let maximumLength = 80

    public static func sanitize(_ raw: String, translation: String) -> String? {
        var text = raw
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let wrappers = CharacterSet(charactersIn: "\"'“”「」『』*`")
        text = text.trimmingCharacters(in: wrappers).trimmingCharacters(in: .whitespaces)
        for prefix in ["Note:", "NOTE:", "Brief:", "BRIEF:", "メモ:", "補足:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty, text != "-", text != "ー", text != "—" else { return nil }
        guard TranslationResultValidator.isUseful(original: translation, translated: text) else { return nil }
        if text.count > maximumLength {
            text = String(text.prefix(maximumLength - 1)) + "…"
        }
        return text
    }
}
