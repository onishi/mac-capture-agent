import CoreGraphics
import Foundation

/// Estimates whether the screen is being shared (Zoom / Meet / Teams…) by
/// looking for their sharing indicator windows every few seconds. There is no
/// public API for this; the result only drives warnings.
final class ScreenShareMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var sharing = false
    private var pretend = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ambient.privacy.screenshare", qos: .utility)

    var isSharing: Bool {
        lock.withLock { sharing || pretend }
    }

    /// Developer option: behave as if the screen were shared (to test warnings).
    func setPretend(_ value: Bool) {
        lock.withLock { pretend = value }
    }

    func start(interval: TimeInterval = 3) {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let windows = list.map { info in
            WindowInfo(
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                title: info[kCGWindowName as String] as? String ?? ""
            )
        }
        let detected = ScreenShareHeuristics.isSharing(windows)
        let changed = lock.withLock { () -> Bool in
            defer { sharing = detected }
            return sharing != detected
        }
        if changed {
            Log.privacy.info("Screen sharing \(detected ? "detected" : "ended", privacy: .public)")
        }
    }
}
