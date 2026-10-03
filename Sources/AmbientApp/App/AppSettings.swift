import Combine
import Foundation

/// User preferences, persisted in `UserDefaults`. Only preferences are stored —
/// never screen content.
final class AppSettings: ObservableObject {
    private enum Key {
        static let targetLanguage = "targetLanguage"
        static let englishIsFamiliar = "englishIsFamiliar"
        static let performanceMode = "performanceMode"
        static let imageClassification = "imageClassificationEnabled"
        static let excludedApps = "excludedBundleIdentifiers"
    }

    static let supportedTargetLanguages = ["ja", "en", "zh-Hans", "zh-Hant", "ko", "fr", "de", "es", "it", "pt"]

    private let defaults: UserDefaults

    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: Key.targetLanguage) }
    }
    /// When on, English text is never translated (useful for people who read English daily).
    @Published var englishIsFamiliar: Bool {
        didSet { defaults.set(englishIsFamiliar, forKey: Key.englishIsFamiliar) }
    }
    @Published var performanceMode: PerformanceMode {
        didSet { defaults.set(performanceMode.rawValue, forKey: Key.performanceMode) }
    }
    @Published var imageClassificationEnabled: Bool {
        didSet { defaults.set(imageClassificationEnabled, forKey: Key.imageClassification) }
    }
    @Published var excludedBundleIdentifiers: Set<String> {
        didSet { defaults.set(Array(excludedBundleIdentifiers).sorted(), forKey: Key.excludedApps) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let systemLanguage = Locale.preferredLanguages.first.map(LanguageCode.base) ?? "ja"
        targetLanguage = defaults.string(forKey: Key.targetLanguage)
            ?? (Self.supportedTargetLanguages.contains(systemLanguage) ? systemLanguage : "ja")
        englishIsFamiliar = defaults.bool(forKey: Key.englishIsFamiliar)
        performanceMode = defaults.string(forKey: Key.performanceMode).flatMap(PerformanceMode.init(rawValue:)) ?? .balanced
        imageClassificationEnabled = defaults.object(forKey: Key.imageClassification) as? Bool ?? true
        excludedBundleIdentifiers = defaults.stringArray(forKey: Key.excludedApps).map { Set($0) }
            ?? PrivacyPolicy.defaultExcludedBundleIdentifiers
    }

    var pipelineConfiguration: PipelineConfiguration {
        PipelineConfiguration(
            targetLanguage: targetLanguage,
            familiarLanguages: englishIsFamiliar && LanguageCode.base(targetLanguage) != "en" ? ["en"] : [],
            performanceMode: performanceMode,
            imageClassificationEnabled: imageClassificationEnabled,
            privacyPolicy: PrivacyPolicy(excludedBundleIdentifiers: excludedBundleIdentifiers)
        )
    }
}
