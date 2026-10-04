import CoreVideo
import Foundation

/// Settings snapshot the pipeline runs with. A change restarts the pipeline.
struct PipelineConfiguration: Sendable, Equatable {
    var targetLanguage: String
    var familiarLanguages: Set<String>
    var performanceMode: PerformanceMode
    var imageClassificationEnabled: Bool
    var privacyPolicy: PrivacyPolicy
    var briefingEnabled: Bool
    var memoryEnabled: Bool
    /// Draw changed regions, OCR areas, router scores and timings on screen.
    var debugOverlay: Bool = false
}

/// What the pipeline asks the HUD to do.
enum HUDEvent: Sendable {
    case show(HUDMessage, briefingPending: Bool)
    case briefing(messageID: UUID, text: String?)
    /// Debug overlay data (geometry, scores, timings — never text).
    case diagnostics(PipelineDiagnostics, PipelineCounters)
}

/// How a routed translation ended, for counters and diagnostics.
private enum TranslationOutcome {
    case shown
    case cooldown
    case discarded
    case failed
}

/// ScreenCaptureKit frames → change detection → region OCR / classification
/// → AI router → cooldown → translation → HUD.
///
/// Runs entirely off the main thread. Any failure along the way results in
/// nothing being shown (and a debug log entry).
actor AnalysisPipeline {
    typealias Presenter = @Sendable (HUDEvent) async -> Void

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
    private let briefingProvider: (any BriefingProvider)?
    private let memory: (any VisualMemoryStore)?
    private let briefingTimeout: Duration = .seconds(5)

    private var lastDetection: TimeInterval = 0
    private var lastClassification: TimeInterval = 0
    private var wasBlockedByPrivacy = false
    private var counters = PipelineCounters()
    private let clock = ContinuousClock()

    /// Normalized margins added around changed regions so partially changed lines are read completely.
    private let regionPadding = (dx: CGFloat(0.04), dy: CGFloat(0.01))

    init(
        configuration: PipelineConfiguration,
        ocr: OCRService,
        classifier: ImageClassifier,
        languageIdentifier: any LanguageIdentifying,
        adjuster: any InterestAdjusting,
        translator: any TranslationProvider,
        foreground: ForegroundContextProvider,
        briefingProvider: (any BriefingProvider)?,
        memory: (any VisualMemoryStore)?,
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
        ), adjuster: adjuster)
        self.translator = translator
        self.privacy = PrivacyManager(policy: configuration.privacyPolicy)
        self.foreground = foreground
        self.present = present
        self.briefingProvider = configuration.briefingEnabled ? briefingProvider : nil
        self.memory = configuration.memoryEnabled ? memory : nil
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

        counters.framesChecked += 1
        let detectStart = clock.now
        let regions = changeDetector.detect(previous: previous, current: gray)
        let detectMilliseconds = Self.milliseconds(clock.now - detectStart)
        if !regions.isEmpty {
            counters.changesDetected += 1
            Log.pipeline.debug("Change detected: \(regions.count) region(s)")
        }
        guard let toAnalyze = scheduler.ingest(regions, at: frame.timestamp) else {
            if configuration.debugOverlay, !regions.isEmpty {
                var diagnostics = PipelineDiagnostics()
                diagnostics.changedRegions = regions.map(\.rect)
                diagnostics.timings["detect"] = detectMilliseconds
                await present(.diagnostics(diagnostics, counters))
            }
            return
        }
        var diagnostics = PipelineDiagnostics()
        diagnostics.changedRegions = regions.map(\.rect)
        diagnostics.timings["detect"] = detectMilliseconds
        await analyze(toAnalyze, in: current, app: app, diagnostics: diagnostics)
    }

    private func analyze(
        _ regions: [ChangedRegion],
        in frame: AnalyzableFrame,
        app: ForegroundContextProvider.Snapshot,
        diagnostics initialDiagnostics: PipelineDiagnostics
    ) async {
        var diagnostics = initialDiagnostics
        let windowTitle = foreground.windowTitle(for: app.processIdentifier)
        guard privacy.allowsAnalysis(of: app, windowTitle: windowTitle) else {
            await pauseForPrivacy()
            return
        }

        counters.analyses += 1
        let padded = regions.map { $0.expanded(dx: regionPadding.dx, dy: regionPadding.dy) }
        Log.vision.debug("OCR started: \(padded.count) region(s)")
        let ocrStart = clock.now
        let ocrSignpost = Log.signposter.beginInterval("ocr", id: Log.signposter.makeSignpostID())
        let lines = await ocr.recognizeText(in: frame.pixelBuffer, regions: padded)
        let blocks = TextBlockGrouper().group(lines)
        Log.signposter.endInterval("ocr", ocrSignpost)
        diagnostics.timings["ocr"] = Self.milliseconds(clock.now - ocrStart)
        diagnostics.analyzedRegions = padded.map(\.rect)
        diagnostics.textLineCount = lines.count
        diagnostics.textBlockCount = blocks.count
        Log.vision.debug("OCR finished: \(lines.count) line(s), \(blocks.count) block(s)")

        let classifyStart = clock.now
        let categories = await classifyIfUseful(regions: padded, textBlocks: blocks, frame: frame)
        if !categories.isEmpty {
            diagnostics.timings["classify"] = Self.milliseconds(clock.now - classifyStart)
        }

        let context = AnalysisContext(
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            textRegions: blocks,
            visualCategories: categories
        )
        let routeStart = clock.now
        let decision = router.decide(context)
        diagnostics.timings["route"] = Self.milliseconds(clock.now - routeStart)
        let action = decision.selected

        var outcome: TranslationOutcome?
        if action.action == .ignore {
            counters.ignored += 1
        } else {
            Log.pipeline.info("Routed action: \(action.action.rawValue, privacy: .public) importance \(action.importance, format: .fixed(precision: 2))")
            switch action.action {
            case .translate:
                let translateStart = clock.now
                let signpost = Log.signposter.beginInterval("translate", id: Log.signposter.makeSignpostID())
                let result = await translate(action, app: app, windowTitle: windowTitle, timestamp: frame.timestamp)
                Log.signposter.endInterval("translate", signpost)
                diagnostics.timings["translate"] = Self.milliseconds(clock.now - translateStart)
                outcome = result
                switch result {
                case .shown: counters.hudsShown += 1
                case .cooldown: counters.suppressedByCooldown += 1
                case .discarded: counters.ignored += 1
                case .failed: counters.failures += 1
                }
            case .explainTerm, .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson, .ignore:
                // Not implemented yet (the router keeps them below the show threshold).
                break
            }
        }

        if configuration.debugOverlay {
            diagnostics.candidates = decision.candidates.map { candidate in
                let isSelected = candidate == action
                return PipelineDiagnostics.Candidate(
                    action: candidate.action,
                    importance: candidate.importance,
                    region: candidate.region,
                    selected: isSelected,
                    suppressedByCooldown: isSelected && outcome == .cooldown
                )
            }
            await present(.diagnostics(diagnostics, counters))
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
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

    private func translate(_ action: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval) async -> TranslationOutcome {
        guard let text = action.payload else { return .discarded }
        let key = CooldownCache.key(action: action.action, payload: text)
        guard cooldown.checkAndRecord(key, now: timestamp) else {
            Log.pipeline.debug("Suppressed by cooldown")
            return .cooldown
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
                return .discarded
            }
            Log.translation.info("Translated \(source, privacy: .public) → \(self.configuration.targetLanguage, privacy: .public)")
            let message = HUDMessage(
                kind: .translation,
                title: Self.displayName(of: source, in: configuration.targetLanguage),
                original: text,
                detail: translated,
                anchor: action.region,
                features: PersonalizationFeatures(
                    action: action.action,
                    language: action.sourceLanguage,
                    bundleIdentifier: app.bundleIdentifier
                ),
                sourceLanguage: action.sourceLanguage,
                targetLanguage: configuration.targetLanguage,
                confidence: action.confidence
            )
            let briefing = briefingProvider.flatMap { $0.isAvailable ? $0 : nil }
            await present(.show(message, briefingPending: briefing != nil))
            await memory?.remember(VisualMemoryEntry(
                id: message.id,
                timestamp: message.capturedAt,
                application: app.appName,
                bundleIdentifier: app.bundleIdentifier,
                windowTitle: windowTitle,
                sourceLanguage: message.sourceLanguage,
                targetLanguage: message.targetLanguage,
                original: message.original,
                translation: message.detail,
                features: message.features
            ))
            if let briefing {
                requestBriefing(from: briefing, for: message, appName: app.appName)
            }
            return .shown
        } catch {
            Log.translation.error("Translation failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    /// Generates the briefing in the background so the pipeline keeps running.
    private nonisolated func requestBriefing(from provider: any BriefingProvider, for message: HUDMessage, appName: String?) {
        let request = BriefingRequest(
            original: message.original,
            translation: message.detail,
            sourceLanguage: message.sourceLanguage,
            targetLanguage: message.targetLanguage ?? "ja",
            appName: appName
        )
        let present = self.present
        let memory = self.memory
        let timeout = briefingTimeout
        Task.detached(priority: .utility) {
            let text: String? = await withTaskGroup(of: String?.self) { group in
                group.addTask {
                    do {
                        let raw = try await provider.briefing(for: request)
                        return BriefingSanitizer.sanitize(raw, translation: request.translation)
                    } catch {
                        Log.translation.debug("Briefing failed: \(String(describing: error), privacy: .public)")
                        return nil
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                return first
            }
            await present(.briefing(messageID: message.id, text: text))
            if let text {
                await memory?.updateBriefing(text, for: message.id)
            }
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
