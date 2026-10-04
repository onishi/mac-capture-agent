import Combine
import Foundation

/// User preferences, persisted in `UserDefaults`. Only preferences are stored —
/// never screen content. Used from the main thread only.
final class AppSettings: ObservableObject, @unchecked Sendable {
    private enum Key {
        static let targetLanguage = "targetLanguage"
        static let englishIsFamiliar = "englishIsFamiliar"
        static let performanceMode = "performanceMode"
        static let imageClassification = "imageClassificationEnabled"
        static let excludedApps = "excludedBundleIdentifiers"
        static let skippedLanguages = "skippedLanguages"
        static let hudPosition = "hudPosition"
        static let followMouseDisplay = "followMouseDisplay"
        static let personalization = "personalizationModel"
        static let briefing = "briefingEnabled"
        static let memory = "memoryEnabled"
        static let memoryRetention = "memoryRetentionDays"
        static let debugOverlay = "debugOverlay"
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

    /// Languages the user asked never to translate ("Stop translating French").
    @Published var skippedLanguages: Set<String> {
        didSet { defaults.set(Array(skippedLanguages).sorted(), forKey: Key.skippedLanguages) }
    }
    @Published var hudPosition: HUDPosition {
        didSet { defaults.set(hudPosition.rawValue, forKey: Key.hudPosition) }
    }
    /// Capture the display the mouse pointer is on instead of the main display.
    @Published var followMouseDisplay: Bool {
        didSet { defaults.set(followMouseDisplay, forKey: Key.followMouseDisplay) }
    }

    /// One-line context notes from Apple Intelligence (on-device), when available.
    @Published var briefingEnabled: Bool {
        didSet { defaults.set(briefingEnabled, forKey: Key.briefing) }
    }

    /// Archive surfaced intel (text only) for later search.
    @Published var memoryEnabled: Bool {
        didSet { defaults.set(memoryEnabled, forKey: Key.memory) }
    }
    @Published var memoryRetentionDays: Int {
        didSet { defaults.set(memoryRetentionDays, forKey: Key.memoryRetention) }
    }
    static let retentionChoices = [1, 7, 30]
    /// Developer overlay: regions, router scores and timings (never text).
    @Published var debugOverlay: Bool {
        didSet { defaults.set(debugOverlay, forKey: Key.debugOverlay) }
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
        skippedLanguages = Set(defaults.stringArray(forKey: Key.skippedLanguages) ?? [])
        hudPosition = defaults.string(forKey: Key.hudPosition).flatMap(HUDPosition.init(rawValue:)) ?? .nearTarget
        followMouseDisplay = defaults.bool(forKey: Key.followMouseDisplay)
        briefingEnabled = defaults.object(forKey: Key.briefing) as? Bool ?? true
        memoryEnabled = defaults.object(forKey: Key.memory) as? Bool ?? true
        let retention = defaults.integer(forKey: Key.memoryRetention)
        memoryRetentionDays = Self.retentionChoices.contains(retention) ? retention : 7
        debugOverlay = defaults.bool(forKey: Key.debugOverlay)
    }

    // MARK: Personalization (aggregated weights only, never screen content)

    func loadPersonalizationModel() -> PersonalizationModel {
        guard let data = defaults.data(forKey: Key.personalization),
              let model = try? JSONDecoder().decode(PersonalizationModel.self, from: data)
        else { return PersonalizationModel() }
        return model
    }

    func savePersonalizationModel(_ model: PersonalizationModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: Key.personalization)
    }

    var familiarLanguages: Set<String> {
        var languages = skippedLanguages
        if englishIsFamiliar { languages.insert("en") }
        languages.remove(LanguageCode.base(targetLanguage))
        return languages
    }

    var pipelineConfiguration: PipelineConfiguration {
        PipelineConfiguration(
            targetLanguage: targetLanguage,
            familiarLanguages: familiarLanguages,
            performanceMode: performanceMode,
            imageClassificationEnabled: imageClassificationEnabled,
            privacyPolicy: PrivacyPolicy(excludedBundleIdentifiers: excludedBundleIdentifiers),
            briefingEnabled: briefingEnabled,
            memoryEnabled: memoryEnabled,
            debugOverlay: debugOverlay
        )
    }
}
