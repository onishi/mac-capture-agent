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
    private let translationBridge = TranslationBridge()
    private let translationHost: TranslationHostWindow
    private let foreground = ForegroundContextProvider()
    private let ocr = OCRService()
    private let classifier = ImageClassifier()
    private let personalization: PersonalizationStore

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
        overlay.onHover = { [weak self] message in
            self?.recordFeedback(.openedDetails, for: message)
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
        let until = duration.map { Date().addingTimeInterval($0) }
        status = .paused(until: until)
        stopPipeline()
        overlay.hide()
        resumeTask?.cancel()
        resumeTask = nil
        if let duration {
            resumeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
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

    // MARK: Feedback

    /// "Not useful": strongly lowers the score of similar content.
    func markLastMessageNotUseful() {
        guard let message = lastMessage else { return }
        recordFeedback(.dismissedQuickly, for: message)
        recordFeedback(.dismissedQuickly, for: message)
        overlay.hide()
        lastMessage = nil
    }

    /// Never translate the language of the last message again.
    func stopTranslatingLastLanguage() {
        guard let language = lastMessage?.features?.language else { return }
        settings.skippedLanguages.insert(language)
        overlay.hide()
        lastMessage = nil
        Log.app.info("Language skipped by user: \(language, privacy: .public)")
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
        displayFollowTask?.cancel()
        displayFollowTask = nil
        let capture = self.capture
        stopTask = Task { await capture.stop() }
    }

    private func settingsDidChange() {
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
            present: { message in
                await MainActor.run { [weak self] in
                    self?.lastMessage = message
                    overlay.show(message, on: NSScreen.screen(for: displayID), position: settings.hudPosition)
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
