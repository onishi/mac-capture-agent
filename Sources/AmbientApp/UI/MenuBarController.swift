import AppKit
import Combine

/// Status item + menu: status line, pause/resume, settings, quit.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let controller: AppController
    private let openSettings: () -> Void
    private let openArchive: () -> Void
    private let openGuide: () -> Void
    private var statusObservation: AnyCancellable?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(controller: AppController, openSettings: @escaping () -> Void, openArchive: @escaping () -> Void, openGuide: @escaping () -> Void) {
        self.controller = controller
        self.openSettings = openSettings
        self.openArchive = openArchive
        self.openGuide = openGuide
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon(for: controller.status)

        statusObservation = controller.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateIcon(for: status)
            }
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = controller.status

        let statusLine = NSMenuItem(title: Self.title(for: status), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        let isPaused: Bool = {
            if case .paused = status { return true }
            return false
        }()
        let canPause = controller.isRunning

        menu.addItem(item("Pause 5 Minutes", #selector(pauseFiveMinutes), enabled: canPause))
        menu.addItem(item("Pause 30 Minutes", #selector(pauseThirtyMinutes), enabled: canPause))
        menu.addItem(item("Pause Until Tomorrow", #selector(pauseUntilTomorrow), enabled: canPause))
        menu.addItem(item("Pause", #selector(pauseIndefinitely), enabled: canPause))
        menu.addItem(item("Resume", #selector(resume), enabled: isPaused || status == .idle || Self.isFailed(status)))

        if status == .needsPermission {
            menu.addItem(.separator())
            menu.addItem(item("Grant Screen Recording Permission…", #selector(grantPermission)))
            menu.addItem(item("Retry", #selector(resume)))
        }

        if let last = controller.lastMessage {
            menu.addItem(.separator())
            let header = NSMenuItem(title: String(localized: "Last: \(Self.truncated(last.detail))"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(item("Not Useful", #selector(markNotUseful)))
            if last.features?.language != nil {
                menu.addItem(item(verbatim: String(localized: "Stop Translating \(last.title)"), #selector(stopTranslatingLanguage)))
            }
        }

        menu.addItem(.separator())
        menu.addItem(item("Translation Languages…", #selector(openTranslationLanguages)))
        let archive = item("Archive…", #selector(showArchive), key: "k")
        archive.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(archive)
        menu.addItem(item("Preview HUD", #selector(previewHUD)))
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))
        menu.addItem(item("Welcome Guide…", #selector(showGuide)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Ambient Screen Intelligence", #selector(quit), key: "q"))
    }

    // MARK: Actions

    @objc private func pauseFiveMinutes() { controller.pause(for: 5 * 60) }
    @objc private func pauseThirtyMinutes() { controller.pause(for: 30 * 60) }
    @objc private func pauseUntilTomorrow() { controller.pauseUntilTomorrow() }
    @objc private func pauseIndefinitely() { controller.pause(for: nil) }
    @objc private func resume() { Task { await controller.resume() } }
    @objc private func showArchive() { openArchive() }
    @objc private func previewHUD() { controller.showDemoHUD() }
    @objc private func markNotUseful() { controller.markLastMessageNotUseful() }
    @objc private func stopTranslatingLanguage() { controller.stopTranslatingLastLanguage() }
    @objc private func grantPermission() { controller.openScreenRecordingSettings() }
    @objc private func openTranslationLanguages() { controller.openTranslationSettings() }
    @objc private func showSettings() { openSettings() }
    @objc private func showGuide() { openGuide() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Helpers

    /// Literal titles are looked up in Localizable.xcstrings.
    private func item(_ title: String.LocalizationValue, _ action: Selector, enabled: Bool = true, key: String = "") -> NSMenuItem {
        item(verbatim: String(localized: title), action, enabled: enabled, key: key)
    }

    private func item(verbatim title: String, _ action: Selector, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func updateIcon(for status: AppController.Status) {
        let symbol: String
        switch status {
        case .running, .starting: symbol = "viewfinder"
        case .paused, .idle: symbol = "eye.slash"
        case .needsPermission, .failed: symbol = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Ambient Screen Intelligence")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = Self.title(for: status)
    }

    private static func truncated(_ text: String, limit: Int = 32) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return singleLine.count > limit ? String(singleLine.prefix(limit)) + "…" : singleLine
    }

    private static func isFailed(_ status: AppController.Status) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private static func title(for status: AppController.Status) -> String {
        switch status {
        case .idle: return String(localized: "Stopped")
        case .starting: return String(localized: "Starting…")
        case .running: return String(localized: "Running")
        case .paused(let until?):
            let time = timeFormatter.string(from: until)
            if Calendar.current.isDateInTomorrow(until) {
                return String(localized: "Paused until tomorrow \(time)")
            }
            return String(localized: "Paused until \(time)")
        case .paused(nil): return String(localized: "Paused")
        case .needsPermission: return String(localized: "Screen Recording permission required")
        case .failed(let reason): return String(localized: "Error: \(reason)")
        }
    }
}
