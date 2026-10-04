import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let onResetPersonalization: () -> Void
    private let onPurgeMemory: () -> Void

    init(settings: AppSettings, onResetPersonalization: @escaping () -> Void, onPurgeMemory: @escaping () -> Void) {
        self.settings = settings
        self.onResetPersonalization = onResetPersonalization
        self.onPurgeMemory = onPurgeMemory
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, onResetPersonalization: onResetPersonalization, onPurgeMemory: onPurgeMemory)))
        window.title = "Ambient Screen Intelligence Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
