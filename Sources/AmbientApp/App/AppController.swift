import AppKit
import Combine

/// Owns the capture/analysis lifecycle: start, pause (timed or indefinite),
/// resume, and restart when settings change.
@MainActor
final class AppController: ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case running
        case paused(until: Date?)
        case needsPermission
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    /// The most recent HUD message, for menu feedback ("Not useful", "Stop translating …").
    @Published private(set) var lastMessage: HUDMessage?

    let settings: AppSettings
    private let capture = ScreenCaptureManager()
    private let overlay = OverlayWindowController()
    private let debugOverlay = DebugOverlayController()
    private let redactionOverlay = RedactionOverlayController()
    private let screenShare = ScreenShareMonitor()
    /// Opens the archive with a query (set by the app delegate).
    var openArchive: ((String) -> Void)?
    private let translationBridge = TranslationBridge()
    private let translationHost: TranslationHostWindow
    private let foreground = ForegroundContextProvider()
    private let ocr = OCRService()
    private let classifier = ImageClassifier()
    private let personalization: PersonalizationStore
    let briefingProvider = AppleIntelligenceBriefingProvider()
    let memoryStore: IntelStore
    private let reasoner = AppleIntelligenceReasoner()

    private var pipelineTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var settingsObservation: AnyCancellable?
    private var runningConfiguration: PipelineConfiguration?
    private var hasRequestedPermission = false
    private var runningDisplayID: CGDirectDisplayID?
    private var displayFollowTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        translationHost = TranslationHostWindow(bridge: translationBridge)
        personalization = PersonalizationStore(model: settings.loadPersonalizationModel()) { [weak settings] model in
            DispatchQueue.main.async { settings?.savePersonalizationModel(model) }
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AmbientScreenIntelligence", isDirectory: true)
        memoryStore = IntelStore(
            url: directory?.appendingPathComponent("intel.sqlite"),
            retentionDays: settings.memoryRetentionDays,
            userLanguage: settings.targetLanguage,
            embedding: NLTextEmbedding()
        )
        if let legacy = directory?.appendingPathComponent("visual-memory.json") {
            let store = memoryStore
            Task { await store.importLegacyJSON(at: legacy) }
        }
        overlay.onHover = { [weak self] message in
            self?.recordFeedback(.openedDetails, for: message)
        }
        screenShare.setPretend(settings.pretendScreenSharing)
        screenShare.start()
        overlay.onAction = { [weak self] action, message in
            self?.handleHUDAction(action, for: message)
        }
        settingsObservation = settings.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.settingsDidChange() }
            }
    }

    var isRunning: Bool { status == .running || status == .starting }

    // MARK: Lifecycle

    func start() async {
        resumeTask?.cancel()
        resumeTask = nil
        guard !isRunning else { return }

        guard ScreenCaptureManager.hasPermission else {
            if !hasRequestedPermission {
                hasRequestedPermission = true
                ScreenCaptureManager.requestPermission()
            }
            status = .needsPermission
            Log.app.info("Screen Recording permission missing")
            return
        }

        status = .starting
        // Make sure a previous stream is fully stopped before starting a new one.
        await stopTask?.value
        stopTask = nil
        guard status == .starting else { return }
        translationHost.show()
        let configuration = settings.pipelineConfiguration
        do {
            let (frames, displayID) = try await capture.start(options: .init(
                preferredDisplayID: settings.followMouseDisplay ? NSScreen.displayIDUnderMouse : nil,
                framesPerSecond: configuration.performanceMode.captureFramesPerSecond,
                excludedBundleIdentifiers: configuration.privacyPolicy.excludedBundleIdentifiers
            ))
            // A pause requested while starting wins.
            guard status == .starting else {
                await capture.stop()
                return
            }
            let pipeline = makePipeline(configuration: configuration, displayID: displayID)
            runningConfiguration = configuration
            runningDisplayID = displayID
            pipelineTask = Task.detached(priority: .utility) {
                await pipeline.run(frames: frames)
            }
            status = .running
            startFollowingDisplayIfNeeded()
        } catch ScreenCaptureError.permissionDenied {
            status = .needsPermission
        } catch {
            Log.app.error("Failed to start capture: \(error.localizedDescription, privacy: .public)")
            status = .failed("Capture could not start")
        }
    }

    /// Stops capture and analysis. `duration == nil` pauses until resumed manually.
    func pause(for duration: TimeInterval?) {
        pause(until: duration.map { Date().addingTimeInterval($0) })
    }

    /// Pauses until the next morning (see `PauseSchedule`).
    func pauseUntilTomorrow() {
        pause(until: PauseSchedule.untilTomorrow(from: Date()))
    }

    /// Stops capture and analysis until `date` (`nil` = until resumed manually).
    func pause(until date: Date?) {
        status = .paused(until: date)
        stopPipeline()
        overlay.hide()
        resumeTask?.cancel()
        resumeTask = nil
        if let date {
            resumeTask = Task { [weak self] in
                let delay = max(0, date.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self?.resume()
            }
        }
        Log.app.info("Paused")
    }

    func resume() async {
        if case .paused = status { status = .idle }
        if case .failed = status { status = .idle }
        if status == .needsPermission { status = .idle }
        await start()
        Log.app.info("Resumed")
    }

    func shutdown() async {
        resumeTask?.cancel()
        pipelineTask?.cancel()
        pipelineTask = nil
        await capture.stop()
    }

    // MARK: Demo

    /// Shows a sample HUD next to the mouse pointer, to preview the look
    /// without waiting for real foreign-language text.
    func showDemoHUD() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let mouse = NSEvent.mouseLocation
        let frame = screen.frame
        // A text-line sized target just above the pointer (normalized, top-left origin).
        let anchor = CGRect(
            x: (mouse.x - frame.minX) / frame.width - 0.08,
            y: (frame.maxY - mouse.y) / frame.height - 0.04,
            width: 0.22,
            height: 0.03
        ).clampedToUnit()
        let message = HUDMessage(
            kind: .translation,
            title: "French",
            original: "Le musée est fermé le lundi et les jours fériés.",
            detail: "美術館は月曜日と祝日は休館です。",
            anchor: anchor,
            features: nil,
            sourceLanguage: "fr",
            targetLanguage: settings.targetLanguage,
            confidence: 0.97
        )
        overlay.show(message, on: screen, position: settings.hudPosition, briefingPending: true)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            self?.overlay.updateBriefing("訪問前に営業日の確認を", for: message.id)
        }
    }

    // MARK: Feedback

    /// "Not useful": strongly lowers the score of similar content.
    func markLastMessageNotUseful() {
        guard let message = lastMessage else { return }
        recordFeedback(.markedNotUseful, for: message)
        overlay.hide()
        lastMessage = nil
    }

    /// The HUD's More actions.
    private func handleHUDAction(_ action: HUDAction, for message: HUDMessage) {
        switch action {
        case .copy:
            // Taking the information away is the strongest signal of interest.
            recordFeedback(.searched, for: message)
        case .openArchive:
            recordFeedback(.searched, for: message)
            openArchive?(message.detail)
        case .notUseful:
            lastMessage = message
            markLastMessageNotUseful()
        case .skipLanguage:
            lastMessage = message
            stopTranslatingLastLanguage()
        case .markKnown:
            let store = memoryStore
            let term = message.title
            Task { await store.markTermKnown(term) }
            Log.app.info("Term marked as known")
        case .close:
            recordFeedback(.dismissedQuickly, for: message)
        }
    }

    /// Never translate the language of the last message again.
    func stopTranslatingLastLanguage() {
        guard let language = lastMessage?.features?.language else { return }
        settings.skippedLanguages.insert(language)
        overlay.hide()
        lastMessage = nil
        Log.app.info("Language skipped by user: \(language, privacy: .public)")
    }

    /// Opening a record in the archive counts as "searched" (score ++).
    func recordSearch(for entry: VisualMemoryEntry) {
        guard let features = entry.features else { return }
        personalization.record(.searched, for: features)
    }

    func purgeMemory() {
        let store = memoryStore
        Task { await store.removeAll() }
    }

    func resetPersonalization() {
        personalization.reset()
        settings.skippedLanguages.removeAll()
    }

    private func recordFeedback(_ feedback: PersonalizationFeedback, for message: HUDMessage) {
        guard let features = message.features else { return }
        personalization.record(feedback, for: features)
        Log.app.debug("Feedback: \(feedback.rawValue, privacy: .public)")
    }

    func openScreenRecordingSettings() {
        ScreenCaptureManager.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Private

    private func stopPipeline() {
        pipelineTask?.cancel()
        pipelineTask = nil
        runningConfiguration = nil
        runningDisplayID = nil
        debugOverlay.hide()
        redactionOverlay.clear()
        displayFollowTask?.cancel()
        displayFollowTask = nil
        let capture = self.capture
        stopTask = Task { await capture.stop() }
    }

    private func settingsDidChange() {
        screenShare.setPretend(settings.pretendScreenSharing)
        let store = memoryStore
        let retention = settings.memoryRetentionDays
        let language = settings.targetLanguage
        Task { await store.configure(retentionDays: retention, userLanguage: language) }
        guard status == .running else { return }
        if settings.pipelineConfiguration != runningConfiguration {
            Log.app.info("Settings changed, restarting pipeline")
            restart()
        } else if settings.followMouseDisplay {
            startFollowingDisplayIfNeeded()
        }
    }

    private func restart() {
        stopPipeline()
        status = .idle
        Task { await start() }
    }

    /// Restarts capture on the display under the mouse pointer when it changes.
    private func startFollowingDisplayIfNeeded() {
        guard settings.followMouseDisplay, displayFollowTask == nil else { return }
        displayFollowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                guard self.settings.followMouseDisplay else {
                    self.displayFollowTask = nil
                    return
                }
                if self.status == .running,
                   let current = NSScreen.displayIDUnderMouse,
                   let running = self.runningDisplayID,
                   current != running {
                    Log.app.info("Display changed, restarting capture")
                    self.restart()
                    return
                }
            }
        }
    }

    private func makePipeline(configuration: PipelineConfiguration, displayID: CGDirectDisplayID) -> AnalysisPipeline {
        let overlay = self.overlay
        let settings = self.settings
        return AnalysisPipeline(
            configuration: configuration,
            ocr: ocr,
            classifier: classifier,
            languageIdentifier: NLLanguageIdentifier(),
            adjuster: personalization,
            translator: AppleTranslationProvider(bridge: translationBridge),
            foreground: foreground,
            briefingProvider: briefingProvider,
            store: memoryStore,
            reasoner: reasoner,
            screenShare: screenShare,
            displayID: displayID,
            present: { event in
                await MainActor.run { [weak self] in
                    switch event {
                    case .show(let message, let briefingPending):
                        self?.lastMessage = message
                        overlay.show(
                            message,
                            on: NSScreen.screen(for: displayID),
                            position: settings.hudPosition,
                            briefingPending: briefingPending
                        )
                    case .briefing(let messageID, let text):
                        overlay.updateBriefing(text, for: messageID)
                    case .diagnostics(let diagnostics, let counters):
                        self?.debugOverlay.update(diagnostics, counters: counters, on: NSScreen.screen(for: displayID))
                    case .redact(let rects):
                        self?.redactionOverlay.cover(rects, on: NSScreen.screen(for: displayID))
                    }
                }
            }
        )
    }
}

extension NSScreen {
    @MainActor
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? main
    }

    @MainActor
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @MainActor
    static var displayIDUnderMouse: CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) }?.displayID
    }
}
