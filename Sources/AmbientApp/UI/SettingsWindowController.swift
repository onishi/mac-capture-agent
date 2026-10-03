import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let onResetPersonalization: () -> Void

    init(settings: AppSettings, onResetPersonalization: @escaping () -> Void) {
        self.settings = settings
        self.onResetPersonalization = onResetPersonalization
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, onResetPersonalization: onResetPersonalization)))
        window.title = "Ambient Screen Intelligence Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
