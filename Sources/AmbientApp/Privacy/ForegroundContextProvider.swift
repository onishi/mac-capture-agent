import AppKit
import CoreGraphics

/// Tracks the frontmost application without touching the main thread from
/// the analysis pipeline.
final class ForegroundContextProvider: @unchecked Sendable {
    struct Snapshot: Sendable, Equatable {
        let bundleIdentifier: String?
        let appName: String?
        let processIdentifier: pid_t?
    }

    private let lock = NSLock()
    private var snapshot = Snapshot(bundleIdentifier: nil, appName: nil, processIdentifier: nil)
    private var observer: NSObjectProtocol?

    @MainActor
    init() {
        update(with: NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(with: app)
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var current: Snapshot {
        lock.withLock { snapshot }
    }

    /// Title of the frontmost window of `pid`. Available because the app holds
    /// the Screen Recording permission. Used only for privacy filtering and context.
    func windowTitle(for pid: pid_t?) -> String? {
        guard let pid,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let window = windows.first { info in
            (info[kCGWindowOwnerPID as String] as? Int32) == pid && (info[kCGWindowLayer as String] as? Int) == 0
        }
        return window?[kCGWindowName as String] as? String
    }

    private func update(with app: NSRunningApplication?) {
        let next = Snapshot(
            bundleIdentifier: app?.bundleIdentifier,
            appName: app?.localizedName,
            processIdentifier: app?.processIdentifier
        )
        lock.withLock { snapshot = next }
    }
}
