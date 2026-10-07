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
        static let reasoning = "reasoningEnabled"
        static let warnSensitive = "warnSensitiveWhileSharing"
        static let redact = "redactWhileSharing"
        static let pretendSharing = "pretendScreenSharing"
        static let pageTracking = "pageTrackingEnabled"
        static let browserURLs = "readBrowserURLs"
        static let resume = "resumeEnabled"
        static let localKnowledge = "localKnowledgeEnabled"
        static let unitConversion = "unitConversionEnabled"
        static let circleLookup = "circleLookupEnabled"
        static let features = "featureSettings"
        static let aiLog = "aiLogEnabled"
        static let publicFigures = "publicFigureEnabled"
        static let mediaMode = "mediaModeEnabled"
        static let newsMode = "newsModeEnabled"
        static let spoiler = "spoilerLevel"
        static let onboardingCompleted = "onboardingCompleted"
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

    /// Archive surfaced intel (text only) for later search.
    @Published var memoryEnabled: Bool {
        didSet { defaults.set(memoryEnabled, forKey: Key.memory) }
    }
    @Published var memoryRetentionDays: Int {
        didSet { defaults.set(memoryRetentionDays, forKey: Key.memoryRetention) }
    }
    static let retentionChoices = [1, 7, 30]
    /// Experimental: cover secrets with opaque boxes while sharing.
    @Published var redactWhileSharing: Bool {
        didSet { defaults.set(redactWhileSharing, forKey: Key.redact) }
    }
    /// Developer: behave as if the screen were shared (to test warnings).
    @Published var pretendScreenSharing: Bool {
        didSet { defaults.set(pretendScreenSharing, forKey: Key.pretendSharing) }
    }
    /// Record page titles / URLs and reading time for bookmarks and work sessions.
    @Published var pageTrackingEnabled: Bool {
        didSet { defaults.set(pageTrackingEnabled, forKey: Key.pageTracking) }
    }
    /// Read the front tab's URL from browsers (Apple Events; asks permission per browser).
    @Published var readBrowserURLs: Bool {
        didSet { defaults.set(readBrowserURLs, forKey: Key.browserURLs) }
    }
    /// Offer "pick up where you left off" after a break.
    @Published var resumeEnabled: Bool {
        didSet { defaults.set(resumeEnabled, forKey: Key.resume) }
    }
    /// Which kinds of intel are on, and which win when several could be shown (SPEC ST-1/ST-2).
    @Published var features: FeatureSettings {
        didSet {
            if let data = try? JSONEncoder().encode(features) { defaults.set(data, forKey: Key.features) }
        }
    }
    /// Keep every on-device LLM answer for review in the archive's AI LOG (SPEC AL-1).
    @Published var aiLogEnabled: Bool {
        didSet { defaults.set(aiLogEnabled, forKey: Key.aiLog) }
    }

    /// A binding-friendly view of one feature's switch.
    func isEnabled(_ feature: IntelFeature) -> Bool { features.isEnabled(feature) }

    func setEnabled(_ feature: IntelFeature, _ enabled: Bool) {
        features.set(feature, enabled: enabled)
    }

    func move(_ feature: IntelFeature, up: Bool) {
        features.move(feature, up: up)
    }

    func resetFeatureOrder() {
        features.resetOrder()
    }
    @Published var spoilerLevel: SpoilerLevel {
        didSet { defaults.set(spoilerLevel.rawValue, forKey: Key.spoiler) }
    }
    /// Developer overlay: regions, router scores and timings (never text).
    @Published var debugOverlay: Bool {
        didSet { defaults.set(debugOverlay, forKey: Key.debugOverlay) }
    }

    /// Set once the first-run guide has been finished.
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
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
        memoryEnabled = defaults.object(forKey: Key.memory) as? Bool ?? true
        let retention = defaults.integer(forKey: Key.memoryRetention)
        memoryRetentionDays = Self.retentionChoices.contains(retention) ? retention : 7
        debugOverlay = defaults.bool(forKey: Key.debugOverlay)
        redactWhileSharing = defaults.bool(forKey: Key.redact)
        pretendScreenSharing = defaults.bool(forKey: Key.pretendSharing)
        pageTrackingEnabled = defaults.object(forKey: Key.pageTracking) as? Bool ?? true
        readBrowserURLs = defaults.object(forKey: Key.browserURLs) as? Bool ?? true
        resumeEnabled = defaults.object(forKey: Key.resume) as? Bool ?? true
        features = Self.loadFeatures(from: defaults)
        aiLogEnabled = defaults.object(forKey: Key.aiLog) as? Bool ?? true
        spoilerLevel = (defaults.object(forKey: Key.spoiler) as? Int).flatMap(SpoilerLevel.init(rawValue:)) ?? .uptoCurrent
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
    }

    /// Stored feature settings, or — on first launch of v0.11+ — the old
    /// individual switches carried over (an explicit "off" stays off).
    private static func loadFeatures(from defaults: UserDefaults) -> FeatureSettings {
        if let data = defaults.data(forKey: Key.features),
           let stored = try? JSONDecoder().decode(FeatureSettings.self, from: data) {
            return stored
        }
        let legacy: [(String, [IntelFeature])] = [
            (Key.briefing, [.briefing]),
            (Key.reasoning, [.termExplanation, .llmRouter]),
            (Key.warnSensitive, [.sensitiveWarning]),
            (Key.localKnowledge, [.identification]),
            (Key.unitConversion, [.unitConversion]),
            (Key.circleLookup, [.circleLookup]),
            (Key.publicFigures, [.publicFigure]),
            (Key.mediaMode, [.mediaCard, .castOnScreen]),
            (Key.newsMode, [.newsBackground])
        ]
        var settings = FeatureSettings.default
        for (key, features) in legacy where (defaults.object(forKey: key) as? Bool) == false {
            features.forEach { settings.set($0, enabled: false) }
        }
        return settings
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
            memoryEnabled: memoryEnabled,
            features: features,
            aiLogEnabled: memoryEnabled && aiLogEnabled,
            redactWhileSharing: redactWhileSharing,
            debugOverlay: debugOverlay
        )
    }
}
