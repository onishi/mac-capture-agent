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
            onOpen: { [weak controller] entry in controller?.recordSearch(for: entry) }
        ))
        self.archiveWindow = archiveWindow
        controller.openArchive = { [weak archiveWindow] query in
            archiveWindow?.show(query: query)
        }
        controller.openSessions = { [weak archiveWindow] in
            archiveWindow?.show(tab: .sessions)
        }
        menuBar = MenuBarController(
            controller: controller,
            openSettings: { [weak settingsWindow] in settingsWindow?.show() },
            openArchive: { [weak archiveWindow] in archiveWindow?.show() }
        )
        // ⌥⌘K opens the archive from anywhere.
        archiveHotKey = GlobalHotKey(keyCode: kVK_ANSI_K, modifiers: cmdKey | optionKey) { [weak archiveWindow] in
            archiveWindow?.toggle()
        }
        if archiveHotKey == nil {
            Log.app.error("Could not register the ⌥⌘K shortcut")
        }

        Log.app.info("Launched")
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
