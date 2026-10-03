import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private var controller: AppController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon (also set via LSUIElement in Info.plist).
        NSApp.setActivationPolicy(.accessory)

        let controller = AppController(settings: settings)
        let settingsWindow = SettingsWindowController(settings: settings)
        self.controller = controller
        self.settingsWindow = settingsWindow
        menuBar = MenuBarController(controller: controller) { [weak settingsWindow] in
            settingsWindow?.show()
        }

        Log.app.info("Launched")
        Task { await controller.start() }
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
