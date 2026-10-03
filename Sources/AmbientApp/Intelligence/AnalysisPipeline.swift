import CoreVideo
import Foundation

/// Settings snapshot the pipeline runs with. A change restarts the pipeline.
struct PipelineConfiguration: Sendable, Equatable {
    var targetLanguage: String
    var familiarLanguages: Set<String>
    var performanceMode: PerformanceMode
    var imageClassificationEnabled: Bool
    var privacyPolicy: PrivacyPolicy
}

/// ScreenCaptureKit frames → change detection → region OCR / classification
/// → AI router → cooldown → translation → HUD.
///
/// Runs entirely off the main thread. Any failure along the way results in
/// nothing being shown (and a debug log entry).
actor AnalysisPipeline {
    typealias Presenter = @Sendable (HUDMessage) async -> Void

    private let configuration: PipelineConfiguration
    private let frameBuffer = FrameBuffer()
    private var changeDetector = ChangeDetector()
    private var scheduler: AnalysisScheduler
    private var cooldown = CooldownCache(duration: 5 * 60)
    private let ocr: OCRService
    private let classifier: ImageClassifier
    private let router: AIRouter
    private let translator: any TranslationProvider
    private let privacy: PrivacyManager
    private let foreground: ForegroundContextProvider
    private let present: Presenter

    private var lastDetection: TimeInterval = 0
    private var lastClassification: TimeInterval = 0
    private var wasBlockedByPrivacy = false

    /// Normalized margins added around changed regions so partially changed lines are read completely.
    private let regionPadding = (dx: CGFloat(0.04), dy: CGFloat(0.01))

    init(
        configuration: PipelineConfiguration,
        ocr: OCRService,
        classifier: ImageClassifier,
        languageIdentifier: any LanguageIdentifying,
        translator: any TranslationProvider,
        foreground: ForegroundContextProvider,
        present: @escaping Presenter
    ) {
        self.configuration = configuration
        var schedulerConfiguration = AnalysisSchedulerConfiguration()
        schedulerConfiguration.minimumAnalysisInterval = configuration.performanceMode.visionInterval
        self.scheduler = AnalysisScheduler(configuration: schedulerConfiguration)
        self.ocr = ocr
        self.classifier = classifier
        self.router = AIRouter(detector: ForeignTextDetector(
            identifier: languageIdentifier,
            configuration: ForeignTextDetectorConfiguration(
                userLanguage: configuration.targetLanguage,
                familiarLanguages: configuration.familiarLanguages
            )
        ))
        self.translator = translator
        self.privacy = PrivacyManager(policy: configuration.privacyPolicy)
        self.foreground = foreground
        self.present = present
    }

    /// Consumes frames until the stream finishes or the task is cancelled.
    func run(frames: AsyncStream<CapturedFrame>) async {
        for await frame in frames {
            if Task.isCancelled { break }
            // Capture runs at 5–30 fps; change detection only every 0.25–1 s.
            guard frame.timestamp - lastDetection >= configuration.performanceMode.changeDetectionInterval else { continue }
            lastDetection = frame.timestamp
            await process(frame)
        }
        await frameBuffer.reset()
        Log.pipeline.info("Pipeline finished")
    }

    // MARK: - Stages

    private func process(_ frame: CapturedFrame) async {
        let app = foreground.current
        guard privacy.policy.allowsAnalysis(bundleIdentifier: app.bundleIdentifier, windowTitle: nil) else {
            await pauseForPrivacy()
            return
        }
        if wasBlockedByPrivacy {
            wasBlockedByPrivacy = false
            Log.privacy.info("Analysis resumed")
        }

        guard let gray = FrameConverter.grayscale(from: frame.pixelBuffer) else {
            Log.pipeline.error("Unsupported pixel buffer")
            return
        }
        let current = AnalyzableFrame(gray: gray, pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
        // The first frame only establishes a baseline: what was already on
        // screen at launch is not announced.
        guard let previous = await frameBuffer.push(current) else { return }

        let regions = changeDetector.detect(previous: previous, current: gray)
        if !regions.isEmpty {
            Log.pipeline.debug("Change detected: \(regions.count) region(s)")
        }
        guard let toAnalyze = scheduler.ingest(regions, at: frame.timestamp) else { return }
        await analyze(toAnalyze, in: current, app: app)
    }

    private func analyze(_ regions: [ChangedRegion], in frame: AnalyzableFrame, app: ForegroundContextProvider.Snapshot) async {
        let windowTitle = foreground.windowTitle(for: app.processIdentifier)
        guard privacy.allowsAnalysis(of: app, windowTitle: windowTitle) else {
            await pauseForPrivacy()
            return
        }

        let padded = regions.map { $0.expanded(dx: regionPadding.dx, dy: regionPadding.dy) }
        Log.vision.debug("OCR started: \(padded.count) region(s)")
        let lines = await ocr.recognizeText(in: frame.pixelBuffer, regions: padded)
        let blocks = TextBlockGrouper().group(lines)
        Log.vision.debug("OCR finished: \(lines.count) line(s), \(blocks.count) block(s)")

        let categories = await classifyIfUseful(regions: padded, textBlocks: blocks, frame: frame)

        let context = AnalysisContext(
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            textRegions: blocks,
            visualCategories: categories
        )
        let action = router.route(context)
        guard action.action != .ignore else { return }
        Log.pipeline.info("Routed action: \(action.action.rawValue, privacy: .public) importance \(action.importance, format: .fixed(precision: 2))")

        switch action.action {
        case .translate:
            await translate(action, timestamp: frame.timestamp)
        case .explainTerm, .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson, .ignore:
            // Not implemented in v0.1 (the router keeps them below the show threshold).
            break
        }
    }

    private func classifyIfUseful(regions: [ChangedRegion], textBlocks: [RecognizedTextRegion], frame: AnalyzableFrame) async -> [VisualCategory] {
        guard configuration.imageClassificationEnabled,
              frame.timestamp - lastClassification >= configuration.performanceMode.classificationInterval,
              let largest = regions.max(by: { $0.area < $1.area }),
              largest.area >= 0.05
        else { return [] }
        // Text-heavy changes are documents, not pictures.
        let textArea = textBlocks.reduce(CGFloat(0)) { $0 + $1.boundingBox.width * $1.boundingBox.height }
        guard textArea < largest.area * 0.3 else { return [] }

        lastClassification = frame.timestamp
        let categories = await classifier.classify(frame.pixelBuffer, region: largest.rect)
        if !categories.isEmpty {
            Log.vision.debug("Visual categories: \(categories.map(\.rawValue).joined(separator: ","), privacy: .public)")
        }
        return categories
    }

    private func translate(_ action: RoutedAction, timestamp: TimeInterval) async {
        guard let text = action.payload else { return }
        let key = CooldownCache.key(action: action.action, payload: text)
        guard cooldown.checkAndRecord(key, now: timestamp) else {
            Log.pipeline.debug("Suppressed by cooldown")
            return
        }
        let source = action.sourceLanguage ?? "und"
        Log.translation.info("Foreign language detected: \(source, privacy: .public), \(text.count) chars")

        do {
            let translated = try await translator.translate(
                text: text,
                sourceLanguage: action.sourceLanguage,
                targetLanguage: configuration.targetLanguage
            )
            guard TranslationResultValidator.isUseful(original: text, translated: translated) else {
                Log.translation.debug("Translation discarded (empty or identical)")
                return
            }
            Log.translation.info("Translated \(source, privacy: .public) → \(self.configuration.targetLanguage, privacy: .public)")
            let message = HUDMessage(
                kind: .translation,
                title: Self.displayName(of: source, in: configuration.targetLanguage),
                original: text,
                detail: translated,
                anchor: action.region
            )
            await present(message)
        } catch {
            Log.translation.error("Translation failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func pauseForPrivacy() async {
        guard !wasBlockedByPrivacy else { return }
        wasBlockedByPrivacy = true
        // Drop everything derived from the screen while a sensitive app is frontmost.
        await frameBuffer.reset()
        changeDetector.reset()
        scheduler.reset()
        Log.privacy.info("Analysis skipped: sensitive app or window is frontmost")
    }

    private static func displayName(of languageCode: String, in displayLanguage: String) -> String {
        Locale(identifier: displayLanguage).localizedString(forLanguageCode: languageCode)
            ?? Locale(identifier: "en").localizedString(forLanguageCode: languageCode)
            ?? languageCode
    }
}
