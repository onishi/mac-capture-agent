import AppKit
import SwiftUI

@MainActor
final class ArchiveWindowController {
    private var window: NSWindow?
    private let model: ArchiveViewModel

    init(model: ArchiveViewModel) {
        self.model = model
    }

    func toggle() {
        if let window, window.isVisible, window.isKeyWindow {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func show(query: String? = nil, tab: ArchiveTab? = nil) {
        if let query {
            model.query = query
            model.tab = .records
        }
        if let tab { model.tab = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        model.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Archive"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.08, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ArchiveView(model: model))
        window.center()
        window.setFrameAutosaveName("ArchiveWindow")
        return window
    }
}
