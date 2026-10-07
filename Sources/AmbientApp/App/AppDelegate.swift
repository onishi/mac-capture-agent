import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private var controller: AppController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var archiveWindow: ArchiveWindowController?
    private var archiveHotKey: GlobalHotKey?
    private var summaryHotKey: GlobalHotKey?
    private var onboardingWindow: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon (also set via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        let controller = AppController(settings: settings)
        let settingsWindow = SettingsWindowController(
            settings: settings,
            onResetPersonalization: { [weak controller] in controller?.resetPersonalization() },
            onPurgeMemory: { [weak controller] in controller?.purgeMemory() }
        )
        self.controller = controller
        self.settingsWindow = settingsWindow
        let settings = self.settings
        let archiveWindow = ArchiveWindowController(model: ArchiveViewModel(
            store: controller.memoryStore,
            retentionDays: { settings.memoryRetentionDays },
            memoryEnabled: { settings.memoryEnabled },
            answerer: controller.archiveAnswerer,
            askingEnabled: { settings.isEnabled(.archiveQuestion) },
            aiLogEnabled: { settings.memoryEnabled && settings.aiLogEnabled },
            targetLanguage: { settings.targetLanguage },
            onOpen: { [weak controller] entry in controller?.recordSearch(for: entry) }
        ))
        self.archiveWindow = archiveWindow
        controller.openArchive = { [weak archiveWindow] query in
            archiveWindow?.show(query: query)
        }
        controller.openSessions = { [weak archiveWindow] in
            archiveWindow?.show(tab: .sessions)
        }
        let onboardingWindow = OnboardingWindowController { [weak self, weak settingsWindow] in
            OnboardingModel(
                settings: settings,
                appleIntelligenceAvailable: AppleIntelligenceReasoner().isAvailable,
                openSettings: { settingsWindow?.show() },
                onFinish: { self?.finishOnboarding() }
            )
        }
        self.onboardingWindow = onboardingWindow
        menuBar = MenuBarController(
            controller: controller,
            openSettings: { [weak settingsWindow] in settingsWindow?.show() },
            openArchive: { [weak archiveWindow] in archiveWindow?.show() },
            openGuide: { [weak onboardingWindow] in onboardingWindow?.show() }
        )
        // ⌥⌘K opens the archive from anywhere.
        archiveHotKey = GlobalHotKey(keyCode: kVK_ANSI_K, modifiers: cmdKey | optionKey, identifier: 1) { [weak archiveWindow] in
            archiveWindow?.toggle()
        }
        if archiveHotKey == nil {
            Log.app.error("Could not register the ⌥⌘K shortcut")
        }
        // ⌥⌘S summarizes what is on screen (LA-10).
        summaryHotKey = GlobalHotKey(keyCode: kVK_ANSI_S, modifiers: cmdKey | optionKey, identifier: 2) { [weak controller] in
            controller?.summarizeScreen()
        }
        if summaryHotKey == nil {
            Log.app.error("Could not register the ⌥⌘S shortcut")
        }

        Log.app.info("Launched")
        if settings.onboardingCompleted {
            Task { await controller.start() }
        } else {
            // First launch: explain before asking for Screen Recording.
            onboardingWindow.show()
        }
    }

    private func finishOnboarding() {
        let isFirstRun = !settings.onboardingCompleted
        settings.onboardingCompleted = true
        onboardingWindow?.close()
        // Re-opening the guide from the menu must not undo a pause.
        guard isFirstRun, let controller else { return }
        Task { await controller.start() }
    }

    func resetPersonalization() {
        controller?.resetPersonalization()
    }

    func purgeMemory() {
        controller?.purgeMemory()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        Task {
            await controller.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
