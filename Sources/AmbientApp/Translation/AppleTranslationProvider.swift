import Foundation
import Translation

/// On-device translation with Apple's Translation framework.
///
/// * macOS 26+: a `TranslationSession` is created directly from installed models.
/// * macOS 15: sessions can only be obtained through SwiftUI's
///   `.translationTask`, so requests go through `TranslationBridge`.
///
/// Language models are never downloaded implicitly (that would pop up system UI
/// at a random moment). Missing models are reported via `languageNotInstalled`
/// and the user installs them in System Settings.
final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
    private let bridge: TranslationBridge
    private let availability = LanguageAvailability()

    init(bridge: TranslationBridge) {
        self.bridge = bridge
    }

    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        guard let sourceLanguage else {
            throw TranslationProviderError.unsupportedLanguagePair(source: nil, target: targetLanguage)
        }
        let source = Locale.Language(identifier: sourceLanguage)
        let target = Locale.Language(identifier: targetLanguage)

        switch await availability.status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw TranslationProviderError.languageNotInstalled(source: sourceLanguage, target: targetLanguage)
        case .unsupported:
            throw TranslationProviderError.unsupportedLanguagePair(source: sourceLanguage, target: targetLanguage)
        @unknown default:
            throw TranslationProviderError.unavailable
        }

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await session.translate(text)
            return response.targetText
        }
        #endif
        return try await bridge.translate(text, source: source, target: target)
    }
}
