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
    /// Technical-term explanations and LLM judgement of borderline candidates (Apple Intelligence).
    var reasoningEnabled: Bool = true
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

/// How a routed action ended, for counters and diagnostics.
private enum IntelOutcome {
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
    private let store: IntelStore
    private let reasoner: (any TermExplaining & RouterJudging)?
    /// On-device LLM calls (explanations, routing) are rate-limited.
    private var llmLimiter = RateLimiter(minimumInterval: 8)
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
        store: IntelStore,
        reasoner: (any TermExplaining & RouterJudging)?,
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
        self.store = store
        self.reasoner = configuration.reasoningEnabled ? reasoner : nil
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
        var action = decision.selected

        // Second stage: let the on-device LLM judge what the rules were unsure about.
        if action.action == .ignore, let reasoner = activeReasoner,
           let candidate = RouterEscalation.candidates(in: decision).first {
            switch candidate.action {
            case .explainTerm:
                action = candidate   // the explainer decides whether it is worth it
            case .translate:
                if llmLimiter.allow(now: frame.timestamp) {
                    let llmStart = clock.now
                    let show = (try? await reasoner.shouldShow(candidate, appName: app.appName, targetLanguage: configuration.targetLanguage)) ?? false
                    diagnostics.timings["llm"] = Self.milliseconds(clock.now - llmStart)
                    if show { action = RouterEscalation.apply(show: true, to: candidate) }
                }
            case .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson, .ignore:
                break
            }
        }

        var outcome: IntelOutcome?
        switch action.action {
        case .ignore:
            counters.ignored += 1
        case .translate:
            Log.pipeline.info("Routed action: translate importance \(action.importance, format: .fixed(precision: 2))")
            let translateStart = clock.now
            let signpost = Log.signposter.beginInterval("translate", id: Log.signposter.makeSignpostID())
            outcome = await translate(action, app: app, windowTitle: windowTitle, timestamp: frame.timestamp)
            Log.signposter.endInterval("translate", signpost)
            diagnostics.timings["translate"] = Self.milliseconds(clock.now - translateStart)
        case .explainTerm:
            let explainStart = clock.now
            let signpost = Log.signposter.beginInterval("explain", id: Log.signposter.makeSignpostID())
            outcome = await explainTerm(action, app: app, windowTitle: windowTitle, timestamp: frame.timestamp)
            Log.signposter.endInterval("explain", signpost)
            diagnostics.timings["explain"] = Self.milliseconds(clock.now - explainStart)
        case .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson:
            // Not implemented yet (the router keeps them below the show threshold).
            break
        }
        switch outcome {
        case .shown: counters.hudsShown += 1
        case .cooldown: counters.suppressedByCooldown += 1
        case .discarded: counters.ignored += 1
        case .failed: counters.failures += 1
        case nil: break
        }

        if configuration.debugOverlay {
            diagnostics.candidates = decision.candidates.map { candidate in
                let isSelected = action.action != .ignore && candidate.action == action.action && candidate.payload == action.payload
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

    private func translate(_ action: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval) async -> IntelOutcome {
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
            var message = HUDMessage(
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
            let entities = NLEntityExtractor.entities(in: text)
            message = await withReappearance(message, entities: entities)
            let briefing = briefingProvider.flatMap { $0.isAvailable ? $0 : nil }
            await present(.show(message, briefingPending: briefing != nil))
            await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: entities)
            if let briefing {
                requestBriefing(from: briefing, for: message, appName: app.appName)
            }
            return .shown
        } catch {
            Log.translation.error("Translation failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    private var activeReasoner: (any TermExplaining & RouterJudging)? {
        guard let reasoner, reasoner.isAvailable else { return nil }
        return reasoner
    }

    /// Explains a technical term: Knowledge Cache first, then the on-device LLM,
    /// which may also decide the term is not worth explaining (cached too).
    private func explainTerm(_ candidate: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval) async -> IntelOutcome {
        guard let reasoner = activeReasoner, let term = candidate.payload else { return .discarded }
        let canonical = EntityName.canonical(term)
        if await store.shouldSkipTerm(canonical) { return .discarded }
        let key = CooldownCache.key(action: .explainTerm, payload: canonical)
        guard !cooldown.isCoolingDown(key, now: timestamp) else { return .cooldown }

        let explanation: TermExplanation
        if let cached = await store.knowledge(forTerm: canonical) {
            guard cached.summary != TermExplanationSanitizer.declinedMarker else { return .discarded }
            explanation = TermExplanation(shouldExplain: true, expansion: cached.detail, summary: cached.summary)
        } else {
            guard llmLimiter.allow(now: timestamp) else { return .discarded }
            do {
                let raw = try await reasoner.explain(term: term, context: candidate.context ?? term, targetLanguage: configuration.targetLanguage)
                let cleaned = TermExplanationSanitizer.sanitize(raw, term: term)
                await store.saveKnowledge(
                    term: term,
                    summary: cleaned?.summary ?? TermExplanationSanitizer.declinedMarker,
                    detail: cleaned?.expansion,
                    source: "foundation-models"
                )
                guard let cleaned else { return .discarded }
                explanation = cleaned
            } catch {
                Log.pipeline.error("Term explanation failed: \(String(describing: error), privacy: .public)")
                return .failed
            }
        }

        cooldown.record(key, now: timestamp)
        let termEntity = ExtractedEntity(type: .term, name: term)
        var message = HUDMessage(
            kind: .explanation,
            title: term,
            original: explanation.expansion ?? term,
            detail: explanation.summary,
            anchor: candidate.region,
            features: PersonalizationFeatures(action: .explainTerm, language: nil, bundleIdentifier: app.bundleIdentifier),
            sourceLanguage: nil,
            targetLanguage: configuration.targetLanguage
        )
        message = await withReappearance(message, entities: [termEntity])
        await present(.show(message, briefingPending: false))
        await store.noteTermShown(term)
        await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: [termEntity])
        Log.pipeline.info("Term explained (\(term.count) chars)")
        return .shown
    }

    /// Attaches "seen N days ago" when any of the entities appeared before.
    private func withReappearance(_ message: HUDMessage, entities: [ExtractedEntity]) async -> HUDMessage {
        guard configuration.memoryEnabled, !entities.isEmpty else { return message }
        let seen = await store.lastSeen(entities, before: message.capturedAt, excluding: message.id)
        guard Reappearance.daysSince(seen, now: message.capturedAt) != nil else { return message }
        return message.withPreviouslySeen(seen)
    }

    private func rememberIfEnabled(_ message: HUDMessage, app: ForegroundContextProvider.Snapshot, windowTitle: String?, entities: [ExtractedEntity]) async {
        guard configuration.memoryEnabled else { return }
        let isExplanation = message.kind == .explanation
        await store.remember(VisualMemoryEntry(
            id: message.id,
            timestamp: message.capturedAt,
            kind: isExplanation ? .explanation : .translation,
            application: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            sourceLanguage: message.sourceLanguage,
            targetLanguage: message.targetLanguage,
            original: isExplanation && message.original != message.title ? "\(message.title) — \(message.original)" : message.original,
            translation: message.detail,
            features: message.features
        ))
        await store.recordEntities(entities, observationID: message.id)
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
        let memory: IntelStore? = configuration.memoryEnabled ? store : nil
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
