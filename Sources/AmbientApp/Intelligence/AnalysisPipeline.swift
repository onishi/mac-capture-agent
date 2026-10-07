import CoreGraphics
import CoreVideo
import Foundation

/// Settings snapshot the pipeline runs with. A change restarts the pipeline.
struct PipelineConfiguration: Sendable, Equatable {
    var targetLanguage: String
    var familiarLanguages: Set<String>
    var performanceMode: PerformanceMode
    var imageClassificationEnabled: Bool
    var privacyPolicy: PrivacyPolicy
    var memoryEnabled: Bool
    /// Which kinds of intel are on and which win when several qualify (SPEC ST-1/ST-2).
    var features: FeatureSettings = .default
    /// Record every on-device LLM answer for the archive's AI LOG (SPEC AL-1).
    var aiLogEnabled: Bool = false
    /// Experimental: cover secrets with opaque boxes while the screen is shared.
    var redactWhileSharing: Bool = false
    /// Draw changed regions, OCR areas, router scores and timings on screen.
    var debugOverlay: Bool = false
}

/// What the pipeline asks the HUD to do.
enum HUDEvent: Sendable {
    case show(HUDMessage, briefingPending: Bool)
    case briefing(messageID: UUID, text: String?)
    /// Debug overlay data (geometry, scores, timings — never text).
    case diagnostics(PipelineDiagnostics, PipelineCounters)
    /// Normalized rects to cover while sharing (experimental); empty clears.
    case redact([CGRect])
}

typealias PipelineReasoner = TermExplaining & RouterJudging & DeveloperAssisting & RegionDescribing & ScreenSummarizing

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
    private let reasoner: (any PipelineReasoner)?
    private let screenShare: ScreenShareMonitor
    private let page: PageContext
    private let media: MediaContext
    private var castCooldown = CooldownCache(duration: 10 * 60)
    private let identifier: (any VisualIdentifying)?
    /// The Mac's dictionaries, for terms when no LLM is available (LA-5).
    private let dictionary: (any DictionaryLooking)?
    private let faceDetector = FaceDetector()
    /// On-device identification is slower than the other LLM uses; at most every 20 s.
    private var identifyLimiter = RateLimiter(minimumInterval: 20)
    /// Abbreviations defined on screen (memory only, SPEC LA-6).
    private var glossary = AcronymGlossary()
    /// Where the pointer last rested outside Coding Mode (for unit conversion).
    private var lastDwell: (region: CGRect, timestamp: TimeInterval)?
    private var personCooldown = CooldownCache(duration: 24 * 60 * 60)
    private let displayID: CGDirectDisplayID
    private let sensitiveDetector = SensitiveDataDetector()
    private var warningCooldown = CooldownCache(duration: 60)
    private var dwellTracker = PointerDwellTracker()
    private var pendingDwellRegion: CGRect?
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
        reasoner: (any PipelineReasoner)?,
        screenShare: ScreenShareMonitor,
        page: PageContext,
        media: MediaContext,
        identifier: (any VisualIdentifying)?,
        dictionary: (any DictionaryLooking)? = nil,
        displayID: CGDirectDisplayID,
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
        self.briefingProvider = configuration.features.isEnabled(.briefing) ? briefingProvider : nil
        self.store = store
        self.reasoner = reasoner
        self.screenShare = screenShare
        self.page = page
        self.media = media
        let features = configuration.features
        self.identifier = features.isEnabled(.identification) || features.isEnabled(.publicFigure) ? identifier : nil
        self.dictionary = configuration.features.isEnabled(.dictionary) ? dictionary : nil
        self.displayID = displayID
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

        // Interest Region: a pointer resting for 2 s. In Coding Mode it asks for a
        // code summary; elsewhere the region is analyzed first.
        if let pointer = pointerPosition(),
           let dwell = dwellTracker.update(position: pointer, at: frame.timestamp) {
            let region = PointerDwellTracker.region(around: dwell)
            if activeReasoner != nil, AppContextClassifier.classify(bundleIdentifier: app.bundleIdentifier) == .coding {
                pendingDwellRegion = region
            } else {
                scheduler.prioritize(ChangedRegion(rect: region, confidence: 1), at: frame.timestamp)
                lastDwell = (region, frame.timestamp)
            }
        }

        guard let gray = FrameConverter.grayscale(from: frame.pixelBuffer) else {
            Log.pipeline.error("Unsupported pixel buffer")
            return
        }
        let current = AnalyzableFrame(gray: gray, pixelBuffer: frame.pixelBuffer, timestamp: frame.timestamp)
        // The first frame only establishes a baseline: what was already on
        // screen at launch is not announced.
        guard let previous = await frameBuffer.push(current) else { return }

        if let dwellRegion = pendingDwellRegion {
            pendingDwellRegion = nil
            let outcome = await explainCode(in: dwellRegion, frame: current, app: app)
            if outcome == .shown { counters.hudsShown += 1 }
        }

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
        let features = configuration.features
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

        let codes = await ocr.detectQRCodes(in: frame.pixelBuffer, regions: padded)

        // Secrets are never translated, explained or archived; while sharing they trigger a warning.
        let (safeBlocks, findings) = sensitiveDetector.partition(blocks)
        if !findings.isEmpty {
            await handleSensitive(findings, timestamp: frame.timestamp)
        }

        // Learn abbreviations the screen defines, to expand them elsewhere later.
        if features.isEnabled(.glossary) {
            for block in safeBlocks {
                glossary.learn(from: block.text)
            }
        }

        let classifyStart = clock.now
        let classification = await classifyIfUseful(regions: padded, textBlocks: blocks, frame: frame)
        let categories = classification.categories
        if !categories.isEmpty {
            diagnostics.timings["classify"] = Self.milliseconds(clock.now - classifyStart)
        }

        let context = AnalysisContext(
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            textRegions: safeBlocks,
            visualCategories: categories
        )
        let routeStart = clock.now
        // Disabled features are dropped; among the rest the user's priority decides.
        let decision = features.select(from: router.candidates(for: context))
        diagnostics.timings["route"] = Self.milliseconds(clock.now - routeStart)
        var action = decision.selected

        // Second stage: let the on-device LLM judge what the rules were unsure about.
        if action.action == .ignore, let reasoner = activeReasoner,
           let candidate = RouterEscalation.candidates(in: decision).first {
            switch candidate.action {
            case .explainTerm:
                action = candidate   // the explainer decides whether it is worth it
            case .translate:
                if features.isEnabled(.llmRouter), llmLimiter.allow(now: frame.timestamp) {
                    let llmStart = clock.now
                    let subject = candidate.payload ?? ""
                    var show = false
                    do {
                        show = try await reasoner.shouldShow(candidate, appName: app.appName, targetLanguage: configuration.targetLanguage)
                        await logAI(.llmRouter, subject: subject, answer: show ? "show" : "ignore",
                                    outcome: show ? .shown : .declined, since: llmStart, app: app)
                    } catch {
                        await logAI(.llmRouter, subject: subject, answer: Self.describe(error), outcome: .failed, since: llmStart, app: app)
                    }
                    diagnostics.timings["llm"] = Self.milliseconds(clock.now - llmStart)
                    if show { action = RouterEscalation.apply(show: true, to: candidate) }
                }
            case .explainError, .explainCode, .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson, .identifyProduct, .ignore:
                break
            }
        }
        // Without the LLM, an abbreviation defined earlier on screen can still be expanded.
        if action.action == .ignore, activeReasoner == nil, features.isEnabled(.glossary),
           let candidate = decision.candidates.first(where: { candidate in
               candidate.action == .explainTerm && candidate.interestScore.level != .ignore
                   && candidate.payload.flatMap { glossaryDefinition(for: $0, context: candidate.context) } != nil
           }) {
            action = candidate
        }

        // Nothing from the router: the other kinds, in the user's priority order.
        var outcome: IntelOutcome?
        if action.action == .ignore {
            var triedIdentification = false
            for feature in features.ordered([.unitConversion, .qrCode, .castOnScreen, .identification, .publicFigure]) {
                guard outcome == nil else { break }
                switch feature {
                case .unitConversion:
                    if let dwell = lastDwell, frame.timestamp - dwell.timestamp <= 4 {
                        outcome = await showConversions(in: safeBlocks, dwellRegion: dwell.region, timestamp: frame.timestamp)
                        if outcome != nil { lastDwell = nil }
                    }
                case .qrCode:
                    if let code = codes.first {
                        outcome = await showQRCode(code.payload, rect: code.rect, app: app, timestamp: frame.timestamp)
                    }
                case .castOnScreen:
                    outcome = await showCastIfNamed(safeBlocks, app: app, windowTitle: windowTitle, timestamp: frame.timestamp)
                case .identification, .publicFigure:
                    // One pass covers both (pictures first, then a name next to a face).
                    guard !triedIdentification, let identifier, identifier.isAvailable else { continue }
                    triedIdentification = true
                    let identifyStart = clock.now
                    outcome = await identifyLocally(identifier, classification: classification, regions: padded, blocks: safeBlocks,
                                                    frame: frame, app: app, windowTitle: windowTitle)
                    if outcome != nil { diagnostics.timings["identify"] = Self.milliseconds(clock.now - identifyStart) }
                default:
                    break
                }
            }
        }
        switch action.action {
        case .ignore:
            if outcome == nil { counters.ignored += 1 }
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
        case .explainError:
            let explainStart = clock.now
            outcome = await explainError(action, app: app, windowTitle: windowTitle, timestamp: frame.timestamp)
            diagnostics.timings["explain"] = Self.milliseconds(clock.now - explainStart)
        case .explainCode:
            break   // triggered by pointer dwell, not by the router
        case .identifyAnimal, .identifyPlant, .identifyLandmark, .identifyPerson, .identifyProduct:
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

    private func classifyIfUseful(regions: [ChangedRegion], textBlocks: [RecognizedTextRegion], frame: AnalyzableFrame) async -> ImageClassification {
        guard configuration.imageClassificationEnabled,
              frame.timestamp - lastClassification >= configuration.performanceMode.classificationInterval,
              let largest = regions.max(by: { $0.area < $1.area }),
              largest.area >= 0.05
        else { return ImageClassification() }
        // Text-heavy changes are documents, not pictures.
        let textArea = textBlocks.reduce(CGFloat(0)) { $0 + $1.boundingBox.width * $1.boundingBox.height }
        guard textArea < largest.area * 0.3 else { return ImageClassification() }

        lastClassification = frame.timestamp
        let classification = await classifier.classify(frame.pixelBuffer, region: largest.rect)
        if !classification.categories.isEmpty {
            Log.vision.debug("Visual categories: \(classification.categories.map(\.rawValue).joined(separator: ","), privacy: .public)")
        }
        return classification
    }

    private func translate(_ action: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval,
                           explicit: Bool = false) async -> IntelOutcome {
        guard let text = action.payload else { return .discarded }
        let key = CooldownCache.key(action: action.action, payload: text)
        guard passesCooldown(key, now: timestamp, explicit: explicit) else {
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

    // MARK: Coding Mode

    /// Explains an error seen in a terminal / IDE / GitHub.
    /// The on-device LLM first; canned rules (SPEC LA-20) when it is
    /// unavailable, busy or gives nothing usable.
    private func explainError(_ candidate: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval,
                              explicit: Bool = false) async -> IntelOutcome {
        guard let line = candidate.payload else { return .discarded }
        let key = CooldownCache.key(action: .explainError, payload: line)
        guard explicit || !cooldown.isCoolingDown(key, now: timestamp) else { return .cooldown }
        var explanation: ErrorExplanation?
        var source = IntelSource.onDeviceLLM
        if let reasoner = activeReasoner, explicit || llmLimiter.allow(now: timestamp) {
            let start = clock.now
            do {
                let raw = try await reasoner.explainError(line, context: candidate.context ?? line, targetLanguage: configuration.targetLanguage)
                explanation = DeveloperOutputSanitizer.sanitize(raw, errorLine: line)
                let answer = raw.fix.map { "\(raw.cause) ▸ \($0)" } ?? raw.cause
                await logAI(.errorExplanation, subject: line, answer: answer, outcome: explanation == nil ? .filtered : .shown,
                            since: start, app: app)
            } catch {
                Log.pipeline.error("Error explanation failed: \(String(describing: error), privacy: .public)")
                await logAI(.errorExplanation, subject: line, answer: Self.describe(error), outcome: .failed, since: start, app: app)
            }
        }
        if explanation == nil, configuration.features.isEnabled(.errorHints) {
            explanation = ErrorHints.hint(for: line, targetLanguage: configuration.targetLanguage)
            source = .rule
        }
        guard let explanation else { return .discarded }
        cooldown.record(key, now: timestamp)
        let kind = ErrorDetector().detect(in: line)?.kind ?? "Error"
        var detail = explanation.fix.map { "\(explanation.cause)\n▸ \($0)" } ?? explanation.cause
        // Where in the user's own code it happened (LA-21), when the trace shows it.
        if let frame = StackTraceAnalyzer.ownFrame(in: candidate.context ?? line) {
            let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
            detail += (japanese ? "\n⌖ 自分のコード: " : "\n⌖ Your code: ") + frame.display
        }
        let message = HUDMessage(
            kind: .errorAnalysis,
            title: kind,
            original: line,
            detail: detail,
            anchor: candidate.region,
            features: PersonalizationFeatures(action: .explainError, language: nil, bundleIdentifier: app.bundleIdentifier),
            targetLanguage: configuration.targetLanguage,
            source: source
        )
        await present(.show(message, briefingPending: false))
        await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: [])
        Log.pipeline.info("Error explained")
        return .shown
    }

    /// Summarizes the code around a pointer dwell.
    private func explainCode(in region: CGRect, frame: AnalyzableFrame, app: ForegroundContextProvider.Snapshot) async -> IntelOutcome {
        guard activeReasoner != nil, configuration.features.isEnabled(.codeSummary) else { return .discarded }
        let lines = await ocr.recognizeText(in: frame.pixelBuffer, regions: [ChangedRegion(rect: region, confidence: 1)])
        let code = lines
            .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            .map(\.text)
            .joined(separator: "\n")
        return await explainCode(code, region: region, app: app, timestamp: frame.timestamp)
    }

    private func explainCode(_ code: String, region: CGRect, app: ForegroundContextProvider.Snapshot, timestamp: TimeInterval,
                             explicit: Bool = false) async -> IntelOutcome {
        guard let reasoner = activeReasoner else { return .discarded }
        guard code.count >= 40, DeveloperOutputSanitizer.looksLikeCode(code),
              sensitiveDetector.kinds(in: code).isEmpty else { return .discarded }
        let key = CooldownCache.key(action: .explainCode, payload: String(code.prefix(200)))
        guard explicit || (!cooldown.isCoolingDown(key, now: timestamp) && llmLimiter.allow(now: timestamp)) else { return .cooldown }
        let start = clock.now
        let subject = code.split(separator: "\n").first.map(String.init) ?? code
        do {
            let raw = try await reasoner.summarizeCode(code, targetLanguage: configuration.targetLanguage)
            guard let summary = DeveloperOutputSanitizer.sanitize(raw) else {
                await logAI(.codeSummary, subject: subject, answer: raw.summary, outcome: raw.isCode ? .filtered : .declined, since: start, app: app)
                return .discarded
            }
            await logAI(.codeSummary, subject: subject, answer: summary.summary, outcome: .shown, since: start, app: app)
            cooldown.record(key, now: timestamp)
            let firstLine = code.split(separator: "\n").first.map { String($0.prefix(80)) } ?? ""
            let message = HUDMessage(
                kind: .codeSummary,
                title: "CODE",
                original: firstLine,
                detail: summary.summary,
                anchor: region,
                features: PersonalizationFeatures(action: .explainCode, language: nil, bundleIdentifier: app.bundleIdentifier),
                targetLanguage: configuration.targetLanguage
            )
            await present(.show(message, briefingPending: false))
            Log.pipeline.info("Code summarized (\(code.count) chars)")
            return .shown
        } catch {
            Log.pipeline.error("Code summary failed: \(String(describing: error), privacy: .public)")
            await logAI(.codeSummary, subject: subject, answer: Self.describe(error), outcome: .failed, since: start, app: app)
            return .failed
        }
    }

    /// Pointer position normalized to the captured display (top-left origin), via
    /// CoreGraphics so it can be read off the main thread.
    private func pointerPosition() -> CGPoint? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0, bounds.contains(location) else { return nil }
        return CGPoint(x: (location.x - bounds.minX) / bounds.width, y: (location.y - bounds.minY) / bounds.height)
    }

    // MARK: On-device identification (SPEC LA-1 / LA-2)

    /// Animals / plants / landmarks / dishes / products from the classifier's
    /// labels and nearby text, or a public figure named on screen next to a
    /// visible face. Estimates only. Returns nil when nothing was tried.
    private func identifyLocally(
        _ identifier: any VisualIdentifying,
        classification: ImageClassification,
        regions: [ChangedRegion],
        blocks: [RecognizedTextRegion],
        frame: AnalyzableFrame,
        app: ForegroundContextProvider.Snapshot,
        windowTitle: String?,
        explicit: Bool = false
    ) async -> IntelOutcome? {
        let context = blocks.map(\.text).joined(separator: " ")

        if configuration.features.isEnabled(.identification),
           let hint = classification.categories.first(where: { [.animal, .plant, .landmark, .food, .product].contains($0) }),
           let largest = regions.max(by: { $0.area < $1.area }),
           explicit || Double(largest.area) >= IdentificationPolicy.minimumRegionArea {
            let labels = VisualLabelSelector.select(classification.labels, for: hint)
            guard !labels.isEmpty else { return .discarded }
            guard explicit || identifyLimiter.allow(now: frame.timestamp) else { return .cooldown }
            let start = clock.now
            let subject = labels.map(\.readable).joined(separator: ", ")
            do {
                var answer = try await identifier.identify(labels: labels, hint: hint, context: context, targetLanguage: configuration.targetLanguage)
                answer.confidence = IdentificationPolicy.localConfidence(
                    answer, labelConfidence: VisualLabelSelector.topConfidence(labels), nearbyText: context)
                let logged = [answer.name, answer.scientificName].filter { !$0.isEmpty }.joined(separator: " / ")
                    + (answer.facts.isEmpty ? "" : " — " + answer.facts.joined(separator: "; "))
                    + String(format: " (%.2f)", answer.confidence)
                guard IdentificationPolicy.accept(answer, hint: hint) else {
                    await logAI(.identification, subject: subject, answer: logged, outcome: answer.category == "none" ? .declined : .filtered,
                                since: start, app: app)
                    return .discarded
                }
                let key = CooldownCache.key(action: .ignore, payload: "id " + answer.name)
                guard passesCooldown(key, now: frame.timestamp, explicit: explicit) else { return .cooldown }
                await logAI(.identification, subject: subject, answer: logged, outcome: .shown, since: start, app: app)
                let entityType: EntityType
                let action: SuggestedAction
                switch answer.category {
                case "landmark": (entityType, action) = (.landmark, .identifyLandmark)
                case "plant": (entityType, action) = (.species, .identifyPlant)
                case "food", "product": (entityType, action) = (.product, .identifyProduct)
                default: (entityType, action) = (.species, .identifyAnimal)
                }
                var message = HUDMessage(
                    kind: .identification,
                    title: IdentificationPolicy.displayName(answer.name, confidence: answer.confidence, language: configuration.targetLanguage),
                    original: answer.scientificName,
                    detail: answer.facts.prefix(3).joined(separator: "\n"),
                    anchor: largest.rect,
                    features: PersonalizationFeatures(action: action, language: nil, bundleIdentifier: app.bundleIdentifier),
                    targetLanguage: configuration.targetLanguage,
                    confidence: answer.confidence
                )
                let entity = ExtractedEntity(type: entityType, name: answer.name)
                message = await withReappearance(message, entities: [entity])
                await present(.show(message, briefingPending: false))
                await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: [entity])
                Log.pipeline.info("Identified \(answer.category, privacy: .public) on-device (\(labels.count) label(s))")
                return .shown
            } catch {
                Log.pipeline.error("On-device identification failed: \(String(describing: error), privacy: .public)")
                await logAI(.identification, subject: subject, answer: Self.describe(error), outcome: .failed, since: start, app: app)
                return .failed
            }
        }

        guard configuration.features.isEnabled(.publicFigure), !explicit else { return nil }
        let text = ([windowTitle].compactMap { $0 } + blocks.map(\.text)).joined(separator: "\n")
        let people = NLEntityExtractor.entities(in: text).filter { $0.type == .person }
        guard let person = people.first(where: { !personCooldown.isCoolingDown($0.canonicalName, now: frame.timestamp) }) else { return nil }
        var faceVisible = classification.categories.contains(.person)
        if !faceVisible {
            faceVisible = await faceDetector.containsFace(in: frame.pixelBuffer, regions: regions)
        }
        guard faceVisible else { return nil }
        personCooldown.record(person.canonicalName, now: frame.timestamp)

        var profile: PublicFigureAnswer?
        if let cached = await store.knowledge(type: .person, canonical: person.canonicalName) {
            guard cached.summary != TermExplanationSanitizer.declinedMarker else { return .discarded }
            profile = PublicFigureAnswer(isPublicFigure: true, name: cached.name, role: cached.summary,
                                         knownFor: cached.detail?.components(separatedBy: "\n") ?? [], confidence: 1)
        } else {
            guard identifyLimiter.allow(now: frame.timestamp) else { return .cooldown }
            let start = clock.now
            do {
                let answer = try await identifier.publicFigure(named: person.name, context: String(text.prefix(300)), targetLanguage: configuration.targetLanguage)
                let accepted = IdentificationPolicy.accept(answer, nameOnScreen: person.name)
                let logged = answer.isPublicFigure
                    ? "\(answer.name) — \(answer.role); \(answer.knownFor.joined(separator: ", "))" + String(format: " (%.2f)", answer.confidence)
                    : "not a public figure"
                await logAI(.publicFigure, subject: person.name, answer: logged,
                            outcome: accepted ? .shown : (answer.isPublicFigure ? .filtered : .declined), since: start, app: app)
                await store.saveKnowledge(
                    entity: person,
                    summary: accepted ? answer.role : TermExplanationSanitizer.declinedMarker,
                    detail: accepted ? answer.knownFor.prefix(3).joined(separator: "\n") : nil,
                    source: "on-device"
                )
                profile = accepted ? answer : nil
            } catch {
                Log.pipeline.error("Public figure lookup failed: \(String(describing: error), privacy: .public)")
                await logAI(.publicFigure, subject: person.name, answer: Self.describe(error), outcome: .failed, since: start, app: app)
                return .failed
            }
        }
        guard let profile else { return .discarded }
        let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
        let works = profile.knownFor.prefix(3).map { "・" + $0 }.joined(separator: "\n")
        var message = HUDMessage(
            kind: .publicFigure,
            title: profile.name,
            original: profile.role,
            detail: works.isEmpty ? profile.role : (japanese ? "代表作（端末内の推定）\n" : "Known for (on-device estimate)\n") + works,
            anchor: nil,
            features: PersonalizationFeatures(action: .identifyPerson, language: nil, bundleIdentifier: app.bundleIdentifier),
            targetLanguage: configuration.targetLanguage
        )
        message = await withReappearance(message, entities: [person])
        await present(.show(message, briefingPending: false))
        await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: [person])
        Log.pipeline.info("Public figure shown")
        return .shown
    }

    // MARK: Circle to look up (SPEC LA-60)

    /// The user circled `region` (normalized, top-left origin) on the captured
    /// display. An explicit request: the ignore-first threshold and cooldowns
    /// don't apply, and when nothing is found a short "no intel" is shown so
    /// the gesture never seems ignored. Privacy rules still apply.
    func lookUp(region: CGRect) async {
        guard let frame = await frameBuffer.currentFrame else { return }
        let app = foreground.current
        let windowTitle = foreground.windowTitle(for: app.processIdentifier)
        guard privacy.allowsAnalysis(of: app, windowTitle: windowTitle) else { return }
        Log.pipeline.info("Circle lookup requested")

        let target = ChangedRegion(rect: region, confidence: 1)
        let lines = await ocr.recognizeText(in: frame.pixelBuffer, regions: [target])
        let blocks = TextBlockGrouper().group(lines)
        let codes = await ocr.detectQRCodes(in: frame.pixelBuffer, regions: [target])
            .filter { sensitiveDetector.kinds(in: $0.payload).isEmpty }
        let (safeBlocks, _) = sensitiveDetector.partition(blocks)
        let text = safeBlocks
            .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            .map(\.text)
            .joined(separator: "\n")
        if configuration.features.isEnabled(.glossary) {
            for block in safeBlocks {
                glossary.learn(from: block.text)
            }
        }
        let classification = configuration.imageClassificationEnabled
            ? await classifier.classify(frame.pixelBuffer, region: region)
            : ImageClassification()
        let context = AnalysisContext(
            appName: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            textRegions: safeBlocks,
            visualCategories: classification.categories
        )
        let plan = ActiveLookupPlanner.plan(
            qrPayloads: codes.map { $0.payload },
            candidates: router.candidates(for: context),
            text: text,
            conversions: QuickConversions.all(in: text, targetLanguage: configuration.targetLanguage),
            categories: classification.categories,
            canUseLanguageModel: activeReasoner != nil,
            features: configuration.features
        )
        Log.pipeline.debug("Circle lookup: \(text.count) chars, \(classification.labels.count) label(s)")

        let now = frame.timestamp
        var outcome: IntelOutcome?
        switch plan {
        case .qrCode(let payload):
            let rect = codes.first(where: { $0.payload == payload })?.rect ?? region
            outcome = await showQRCode(payload, rect: rect, app: app, timestamp: now, explicit: true)
        case .explainError(let candidate):
            outcome = await explainError(candidate, app: app, windowTitle: windowTitle, timestamp: now, explicit: true)
        case .translate(let candidate):
            outcome = await translate(candidate, app: app, windowTitle: windowTitle, timestamp: now, explicit: true)
        case .convertUnits(let conversions):
            if let first = conversions.first {
                await presentConversions(conversions, first: first, anchor: region)
                outcome = .shown
            }
        case .explainTerm(let candidate):
            outcome = await explainTerm(candidate, app: app, windowTitle: windowTitle, timestamp: now, explicit: true)
        case .explainCode(let code):
            outcome = await explainCode(code, region: region, app: app, timestamp: now, explicit: true)
        case .identify:
            if let identifier, identifier.isAvailable {
                outcome = await identifyLocally(identifier, classification: classification, regions: [target], blocks: safeBlocks,
                                                frame: frame, app: app, windowTitle: windowTitle, explicit: true)
            }
        case .describe(let described):
            outcome = await describeRegion(described, region: region, app: app)
        case .nothing:
            break
        }
        // The specific path found nothing usable: fall back to "what is this?".
        var describedAlready = false
        if case .describe = plan { describedAlready = true }
        if outcome != .shown, plan != .nothing, !describedAlready, text.count >= ActiveLookupPlanner.minimumDescribeLength {
            outcome = await describeRegion(text, region: region, app: app)
        }
        if outcome == .shown {
            counters.hudsShown += 1
        } else {
            let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
            await present(.show(HUDMessage(
                kind: .noIntel,
                title: "NO INTEL",
                original: "",
                detail: japanese ? "ここからは何も分かりませんでした" : "Nothing found here",
                anchor: region,
                targetLanguage: configuration.targetLanguage
            ), briefingPending: false))
        }
    }

    /// "What is this?" for circled text, by the on-device model.
    private func describeRegion(_ text: String, region: CGRect, app: ForegroundContextProvider.Snapshot) async -> IntelOutcome {
        guard let reasoner = activeReasoner, configuration.features.isEnabled(.regionSummary) else { return .discarded }
        let input = String(text.prefix(RegionDescription.maximumInputLength))
        let subject = input.split(separator: "\n").first.map(String.init) ?? input
        let start = clock.now
        do {
            let raw = try await reasoner.describe(text: input, appName: app.appName, targetLanguage: configuration.targetLanguage)
            guard let summary = RegionDescription.sanitize(raw, input: input) else {
                await logAI(.regionSummary, subject: subject, answer: raw, outcome: .filtered, since: start, app: app)
                return .discarded
            }
            await logAI(.regionSummary, subject: subject, answer: summary, outcome: .shown, since: start, app: app)
            let firstLine = input.split(separator: "\n").first.map { String($0.prefix(80)) } ?? ""
            let message = HUDMessage(
                kind: .regionSummary,
                title: "TARGET",
                original: firstLine,
                detail: summary,
                anchor: region,
                features: PersonalizationFeatures(action: .explainTerm, language: nil, bundleIdentifier: app.bundleIdentifier),
                targetLanguage: configuration.targetLanguage
            )
            await present(.show(message, briefingPending: false))
            Log.pipeline.info("Circled area described (\(input.count) chars)")
            return .shown
        } catch {
            Log.pipeline.error("Region description failed: \(String(describing: error), privacy: .public)")
            await logAI(.regionSummary, subject: subject, answer: Self.describe(error), outcome: .failed, since: start, app: app)
            return .failed
        }
    }

    // MARK: Summarize the screen (SPEC LA-10)

    /// On request (⌥⌘S): the visible text of the latest frame, in reading
    /// order and without secrets, condensed into up to three lines by the
    /// on-device model, shown and kept in the archive.
    func summarizeScreen() async {
        let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
        func notice(_ ja: String, _ en: String) async {
            await present(.show(HUDMessage(kind: .noIntel, title: "NO INTEL", original: "", detail: japanese ? ja : en,
                                           anchor: nil, targetLanguage: configuration.targetLanguage), briefingPending: false))
        }
        guard configuration.features.isEnabled(.screenSummary) else { return }
        guard let reasoner = activeReasoner else {
            await notice("要約には Apple Intelligence が必要です", "Summaries need Apple Intelligence")
            return
        }
        guard let frame = await frameBuffer.currentFrame else { return }
        let app = foreground.current
        let windowTitle = foreground.windowTitle(for: app.processIdentifier)
        guard privacy.allowsAnalysis(of: app, windowTitle: windowTitle) else { return }
        Log.pipeline.info("Screen summary requested")

        let whole = ChangedRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 1)
        let lines = await ocr.recognizeText(in: frame.pixelBuffer, regions: [whole])
        let (safeBlocks, _) = sensitiveDetector.partition(TextBlockGrouper().group(lines))
        let text = safeBlocks
            .sorted { ($0.boundingBox.minY, $0.boundingBox.minX) < ($1.boundingBox.minY, $1.boundingBox.minX) }
            .map(\.text)
            .joined(separator: "\n")
        guard text.count >= ScreenSummary.minimumInputLength else {
            await notice("要約するほどの文章がありません", "Not enough text to summarize")
            return
        }
        let subject = windowTitle ?? app.appName ?? "Screen"
        let start = clock.now
        do {
            let raw = try await reasoner.summarize(text: text, title: windowTitle, targetLanguage: configuration.targetLanguage)
            guard let summary = ScreenSummary.sanitize(raw, input: text) else {
                await logAI(.screenSummary, subject: subject, answer: raw, outcome: .filtered, since: start, app: app)
                await notice("うまく要約できませんでした", "Could not summarize this")
                return
            }
            await logAI(.screenSummary, subject: subject, answer: summary.joined(separator: " / "), outcome: .shown, since: start, app: app)
            let message = HUDMessage(
                kind: .screenSummary,
                title: "SUMMARY",
                original: subject,
                detail: summary.map { "・" + $0 }.joined(separator: "\n"),
                anchor: nil,
                features: PersonalizationFeatures(action: .explainTerm, language: nil, bundleIdentifier: app.bundleIdentifier),
                targetLanguage: configuration.targetLanguage
            )
            await present(.show(message, briefingPending: false))
            await rememberIfEnabled(message, app: app, windowTitle: windowTitle, entities: [])
            counters.hudsShown += 1
            Log.pipeline.info("Screen summarized (\(text.count) chars)")
        } catch {
            Log.pipeline.error("Screen summary failed: \(String(describing: error), privacy: .public)")
            await logAI(.screenSummary, subject: subject, answer: Self.describe(error), outcome: .failed, since: start, app: app)
            await notice("要約に失敗しました", "The summary failed")
        }
    }

    // MARK: Unit conversion (SPEC LA-15)

    /// Imperial quantities, times in other zones, timestamps and dates in the
    /// text under a resting pointer, converted for the user (LA-15〜LA-18).
    private func showConversions(in blocks: [RecognizedTextRegion], dwellRegion: CGRect, timestamp: TimeInterval) async -> IntelOutcome? {
        guard configuration.features.isEnabled(.unitConversion) else { return nil }
        for block in blocks where block.boundingBox.intersects(dwellRegion) {
            let conversions = QuickConversions.all(in: block.text, targetLanguage: configuration.targetLanguage)
            guard let first = conversions.first else { continue }
            let key = CooldownCache.key(action: .ignore, payload: "convert " + conversions.map(\.original).joined(separator: "|"))
            guard cooldown.checkAndRecord(key, now: timestamp) else { return .cooldown }
            await presentConversions(conversions, first: first, anchor: block.boundingBox)
            return .shown
        }
        return nil
    }

    private func presentConversions(_ conversions: [UnitConversion], first: UnitConversion, anchor: CGRect?) async {
        let message = HUDMessage(
            kind: .conversion,
            title: first.converted,
            original: first.original,
            detail: conversions.map { "\($0.original) → \($0.converted)" }.joined(separator: "\n"),
            anchor: anchor,
            targetLanguage: configuration.targetLanguage
        )
        await present(.show(message, briefingPending: false))
        Log.pipeline.info("Units converted (\(conversions.count))")
    }

    // MARK: Movie / Anime mode

    /// A character or performer of the current work named in subtitles / credits.
    /// Uses the cast already fetched for the work card (no extra network).
    private func showCastIfNamed(_ blocks: [RecognizedTextRegion], app: ForegroundContextProvider.Snapshot,
                                 windowTitle: String?, timestamp: TimeInterval) async -> IntelOutcome? {
        let current = media.current
        guard !current.cast.isEmpty,
              AppContextClassifier.classify(bundleIdentifier: app.bundleIdentifier, windowTitle: windowTitle) == .media else { return nil }
        for block in blocks {
            for member in CastMatcher.matches(current.cast, in: block.text) {
                guard castCooldown.checkAndRecord(EntityName.canonical(member.character), now: timestamp) else { continue }
                let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
                let message = HUDMessage(
                    kind: .cast,
                    title: member.character,
                    original: current.title ?? "",
                    detail: (japanese ? "演: " : "Played by ") + member.performer,
                    anchor: block.boundingBox,
                    targetLanguage: configuration.targetLanguage
                )
                await present(.show(message, briefingPending: false))
                return .shown
            }
        }
        return nil
    }

    // MARK: QR codes

    /// Shows where an on-screen QR code leads (people can't read QR codes on a screen).
    private func showQRCode(_ payload: String, rect: CGRect, app: ForegroundContextProvider.Snapshot, timestamp: TimeInterval,
                            explicit: Bool = false) async -> IntelOutcome {
        guard let content = QRContent.display(payload), sensitiveDetector.kinds(in: payload).isEmpty else { return .discarded }
        let key = CooldownCache.key(action: .ignore, payload: "qr " + payload)
        guard passesCooldown(key, now: timestamp, explicit: explicit) else { return .cooldown }
        let message = HUDMessage(
            kind: .qrCode,
            title: content.isURL ? "LINK" : "TEXT",
            original: content.isURL ? "QR → URL" : "QR → TEXT",
            detail: content.text,
            anchor: rect,
            targetLanguage: configuration.targetLanguage
        )
        await present(.show(message, briefingPending: false))
        Log.pipeline.info("QR code shown")
        return .shown
    }

    // MARK: Sensitive data

    private func handleSensitive(_ findings: [SensitiveFinding], timestamp: TimeInterval) async {
        Log.privacy.info("Sensitive data detected: \(findings.count) item(s)")
        guard screenShare.isSharing else { return }
        let high = findings.filter { $0.kind.isHighSeverity }
        guard !high.isEmpty else { return }
        if configuration.redactWhileSharing {
            await present(.redact(high.compactMap(\.region)))
        }
        guard configuration.features.isEnabled(.sensitiveWarning),
              let first = high.first,
              warningCooldown.checkAndRecord("warn:\(first.kind.rawValue)", now: timestamp) else { return }
        let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
        let kinds = Array(Set(high.map(\.kind))).sorted { $0.rawValue < $1.rawValue }
        let names = kinds.map { japanese ? $0.japaneseLabel : $0.label }.joined(separator: japanese ? "、" : ", ")
        let message = HUDMessage(
            kind: .securityWarning,
            title: japanese ? "機密情報" : "Sensitive information",
            original: japanese ? "画面共有中" : "Screen sharing is on",
            detail: japanese ? "\(names) が表示されています" : "\(names) is visible on screen",
            anchor: first.region,
            targetLanguage: configuration.targetLanguage
        )
        await present(.show(message, briefingPending: false))
        counters.hudsShown += 1
        Log.privacy.info("Sensitive data warning shown")
    }

    private var activeReasoner: (any PipelineReasoner)? {
        guard let reasoner, reasoner.isAvailable else { return nil }
        return reasoner
    }

    /// Keeps an on-device LLM answer for the archive's AI LOG (SPEC AL-1), when enabled.
    private func logAI(_ feature: IntelFeature, subject: String, answer: String, outcome: AIAnswerOutcome,
                       since start: ContinuousClock.Instant, app: ForegroundContextProvider.Snapshot?) async {
        guard configuration.aiLogEnabled else { return }
        await store.recordAIAnswer(AIAnswerRecord(
            feature: feature,
            subject: subject,
            answer: answer,
            outcome: outcome,
            durationMilliseconds: Int(Self.milliseconds(clock.now - start)),
            application: app?.appName
        ))
    }

    /// The error's type only (no screen text), for the AI LOG.
    static func describe(_ error: Error) -> String {
        "error: " + String(describing: type(of: error))
    }

    /// Automatic intel respects the cooldown; an explicit request (circle) always passes but is still recorded.
    private func passesCooldown(_ key: String, now: TimeInterval, explicit: Bool) -> Bool {
        guard explicit else { return cooldown.checkAndRecord(key, now: now) }
        cooldown.record(key, now: now)
        return true
    }

    /// A definition of the abbreviation seen earlier on screen, unless the
    /// text around it already defines it (the page explains itself).
    private func glossaryDefinition(for term: String, context: String?) -> AcronymDefinition? {
        guard configuration.features.isEnabled(.glossary), let definition = glossary.lookup(term) else { return nil }
        if let context, context.localizedCaseInsensitiveContains(definition.expansion) { return nil }
        return definition
    }

    /// Explains a technical term: Knowledge Cache first, then the on-device LLM,
    /// which may also decide the term is not worth explaining (cached too).
    /// Without the LLM, an abbreviation defined earlier on screen is expanded
    /// from the in-memory glossary (SPEC LA-6).
    private func explainTerm(_ candidate: RoutedAction, app: ForegroundContextProvider.Snapshot, windowTitle: String?, timestamp: TimeInterval,
                             explicit: Bool = false) async -> IntelOutcome {
        guard let term = candidate.payload else { return .discarded }
        let definition = glossaryDefinition(for: term, context: candidate.context)
        let reasoner = activeReasoner
        // Without the LLM and the glossary, the Mac's dictionaries — only when asked or clearly worth it.
        var dictionaryEntry: String?
        if reasoner == nil, definition == nil, let dictionary, explicit || candidate.interestScore.level == .show {
            dictionaryEntry = dictionary.definition(of: term)
        }
        guard reasoner != nil || definition != nil || dictionaryEntry != nil else { return .discarded }
        let canonical = EntityName.canonical(term)
        if !explicit, await store.shouldSkipTerm(canonical) { return .discarded }
        let key = CooldownCache.key(action: .explainTerm, payload: canonical)
        guard explicit || !cooldown.isCoolingDown(key, now: timestamp) else { return .cooldown }

        var explanation: TermExplanation
        var source = IntelSource.onDeviceLLM
        if let definition, reasoner == nil {
            source = .rule
            let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
            explanation = TermExplanation(
                shouldExplain: true,
                expansion: definition.expansion,
                summary: japanese ? "以前の画面に書かれていた略語の定義です" : "Defined earlier on your screen"
            )
        } else if let dictionaryEntry, reasoner == nil {
            source = .dictionary
            explanation = TermExplanation(shouldExplain: true, expansion: nil, summary: dictionaryEntry)
        } else if let cached = await store.knowledge(forTerm: canonical) {
            guard cached.summary != TermExplanationSanitizer.declinedMarker else { return .discarded }
            explanation = TermExplanation(shouldExplain: true, expansion: cached.detail, summary: cached.summary)
        } else {
            guard let reasoner, explicit || llmLimiter.allow(now: timestamp) else { return .discarded }
            let start = clock.now
            do {
                var context = candidate.context ?? term
                if let definition { context = "\(definition.acronym) = \(definition.expansion). " + context }
                let raw = try await reasoner.explain(term: term, context: context, targetLanguage: configuration.targetLanguage)
                let cleaned = TermExplanationSanitizer.sanitize(raw, term: term)
                let logged = [raw.expansion, raw.summary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
                await logAI(.termExplanation, subject: term, answer: raw.shouldExplain ? logged : "not worth explaining",
                            outcome: !raw.shouldExplain ? .declined : (cleaned == nil ? .filtered : .shown), since: start, app: app)
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
                await logAI(.termExplanation, subject: term, answer: Self.describe(error), outcome: .failed, since: start, app: app)
                return .failed
            }
        }

        if explanation.expansion == nil, let definition {
            explanation = TermExplanation(shouldExplain: true, expansion: definition.expansion, summary: explanation.summary)
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
            targetLanguage: configuration.targetLanguage,
            source: source
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
        guard ![.securityWarning, .qrCode, .resume, .mediaInfo, .cast, .newsContext, .conversion, .regionSummary, .noIntel].contains(message.kind) else { return }
        let isExplanation = message.kind == .explanation
        let kind: VisualMemoryEntry.Kind
        switch message.kind {
        case .translation, .securityWarning, .qrCode, .resume, .mediaInfo, .cast, .newsContext, .conversion, .regionSummary, .noIntel:
            kind = .translation
        case .screenSummary: kind = .summary
        case .explanation: kind = .explanation
        case .errorAnalysis: kind = .errorAnalysis
        case .codeSummary: kind = .codeSummary
        case .identification: kind = .identification
        case .publicFigure: kind = .publicFigure
        }
        await store.remember(VisualMemoryEntry(
            id: message.id,
            timestamp: message.capturedAt,
            kind: kind,
            application: app.appName,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: windowTitle,
            url: page.currentURL,
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
        let log: IntelStore? = configuration.aiLogEnabled ? store : nil
        let timeout = briefingTimeout
        Task.detached(priority: .utility) {
            /// What happened, for the AI LOG: the raw answer, an error, or a timeout.
            enum BriefingResult: Sendable {
                case answer(raw: String, cleaned: String?)
                case failed(String)
                case timedOut
            }
            let started = Date()
            let result: BriefingResult = await withTaskGroup(of: BriefingResult.self) { group in
                group.addTask {
                    do {
                        let raw = try await provider.briefing(for: request)
                        return .answer(raw: raw, cleaned: BriefingSanitizer.sanitize(raw, translation: request.translation))
                    } catch {
                        Log.translation.debug("Briefing failed: \(String(describing: error), privacy: .public)")
                        return .failed(AnalysisPipeline.describe(error))
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                group.cancelAll()
                return first
            }
            var text: String?
            if case .answer(_, let cleaned) = result { text = cleaned }
            await present(.briefing(messageID: message.id, text: text))
            if let text {
                await memory?.updateBriefing(text, for: message.id)
            }
            if let log {
                let (answer, outcome): (String, AIAnswerOutcome)
                switch result {
                case .answer(let raw, let cleaned): (answer, outcome) = (cleaned ?? raw, cleaned == nil ? .filtered : .shown)
                case .failed(let reason): (answer, outcome) = (reason, .failed)
                case .timedOut: (answer, outcome) = ("timed out", .failed)
                }
                await log.recordAIAnswer(AIAnswerRecord(
                    feature: .briefing,
                    subject: message.detail,
                    answer: answer,
                    outcome: outcome,
                    durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000),
                    application: appName
                ))
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
