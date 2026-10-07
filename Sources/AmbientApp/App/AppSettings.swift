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
    /// Term explanations and LLM judgement of borderline text (Apple Intelligence).
    @Published var reasoningEnabled: Bool {
        didSet { defaults.set(reasoningEnabled, forKey: Key.reasoning) }
    }
    /// Warn when secrets appear on screen while it is being shared.
    @Published var warnSensitiveWhileSharing: Bool {
        didSet { defaults.set(warnSensitiveWhileSharing, forKey: Key.warnSensitive) }
    }
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
    /// On-device identification and knowledge (estimates; Apple Intelligence + image classification).
    @Published var localKnowledgeEnabled: Bool {
        didSet { defaults.set(localKnowledgeEnabled, forKey: Key.localKnowledge) }
    }
    /// Convert imperial quantities where the pointer rests.
    @Published var unitConversionEnabled: Bool {
        didSet { defaults.set(unitConversionEnabled, forKey: Key.unitConversion) }
    }
    /// Hold ⌥ and circle something to look it up (LOCAL_AI.md LA-60).
    @Published var circleLookupEnabled: Bool {
        didSet { defaults.set(circleLookupEnabled, forKey: Key.circleLookup) }
    }
    /// Look up public figures whose names appear on screen (text only).
    @Published var publicFigureEnabled: Bool {
        didSet { defaults.set(publicFigureEnabled, forKey: Key.publicFigures) }
    }
    /// Movie / Anime mode: work card and cast on screen.
    @Published var mediaModeEnabled: Bool {
        didSet { defaults.set(mediaModeEnabled, forKey: Key.mediaMode) }
    }
    /// News mode: background of the story being read.
    @Published var newsModeEnabled: Bool {
        didSet { defaults.set(newsModeEnabled, forKey: Key.newsMode) }
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
        briefingEnabled = defaults.object(forKey: Key.briefing) as? Bool ?? true
        memoryEnabled = defaults.object(forKey: Key.memory) as? Bool ?? true
        let retention = defaults.integer(forKey: Key.memoryRetention)
        memoryRetentionDays = Self.retentionChoices.contains(retention) ? retention : 7
        debugOverlay = defaults.bool(forKey: Key.debugOverlay)
        reasoningEnabled = defaults.object(forKey: Key.reasoning) as? Bool ?? true
        warnSensitiveWhileSharing = defaults.object(forKey: Key.warnSensitive) as? Bool ?? true
        redactWhileSharing = defaults.bool(forKey: Key.redact)
        pretendScreenSharing = defaults.bool(forKey: Key.pretendSharing)
        pageTrackingEnabled = defaults.object(forKey: Key.pageTracking) as? Bool ?? true
        readBrowserURLs = defaults.object(forKey: Key.browserURLs) as? Bool ?? true
        resumeEnabled = defaults.object(forKey: Key.resume) as? Bool ?? true
        localKnowledgeEnabled = defaults.object(forKey: Key.localKnowledge) as? Bool ?? true
        unitConversionEnabled = defaults.object(forKey: Key.unitConversion) as? Bool ?? true
        circleLookupEnabled = defaults.object(forKey: Key.circleLookup) as? Bool ?? true
        publicFigureEnabled = defaults.object(forKey: Key.publicFigures) as? Bool ?? true
        mediaModeEnabled = defaults.object(forKey: Key.mediaMode) as? Bool ?? true
        newsModeEnabled = defaults.object(forKey: Key.newsMode) as? Bool ?? true
        spoilerLevel = (defaults.object(forKey: Key.spoiler) as? Int).flatMap(SpoilerLevel.init(rawValue:)) ?? .uptoCurrent
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
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
            reasoningEnabled: reasoningEnabled,
            warnSensitiveWhileSharing: warnSensitiveWhileSharing,
            redactWhileSharing: redactWhileSharing,
            localKnowledgeEnabled: localKnowledgeEnabled,
            unitConversionEnabled: unitConversionEnabled,
            publicFigureEnabled: publicFigureEnabled,
            debugOverlay: debugOverlay
        )
    }
}
