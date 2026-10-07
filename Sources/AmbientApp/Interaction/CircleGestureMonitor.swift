import CoreGraphics
import Foundation

/// Watches for "hold ⌥ and circle something" (SPEC LA-60).
///
/// Polls the pointer and the modifier state with CoreGraphics, off the main
/// thread: no event tap, so no Input Monitoring / Accessibility permission is
/// expected (to be confirmed on a real Mac). Polls at ~60 Hz only while ⌥ is
/// held, otherwise ~16 Hz just to notice the key.
final class CircleGestureMonitor: @unchecked Sendable {
    typealias TrailHandler = @Sendable ([CGPoint]) async -> Void
    typealias CircleHandler = @Sendable (CGRect) async -> Void

    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// `onTrail` receives the stroke so far (normalized, top-left origin; empty clears it).
    /// `onCircle` receives the circled area on the display (normalized, top-left origin).
    func start(displayID: CGDirectDisplayID, onTrail: @escaping TrailHandler, onCircle: @escaping CircleHandler) {
        stop()
        let newTask = Task.detached(priority: .userInitiated) {
            await Self.run(displayID: displayID, onTrail: onTrail, onCircle: onCircle)
        }
        lock.withLock { task = newTask }
    }

    func stop() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }

    /// ⌥ alone, with no mouse button pressed (⌥-drag in apps must not count).
    static func triggerActive() -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskShift) else { return false }
        return !CGEventSource.buttonState(.combinedSessionState, button: .left)
            && !CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    private static func run(displayID: CGDirectDisplayID, onTrail: TrailHandler, onCircle: CircleHandler) async {
        var tracker = CircleGestureTracker()
        let clock = ContinuousClock()
        let origin = clock.now
        var lastTrail: TimeInterval = 0
        var showingTrail = false
        /// A few samples before drawing anything, so pressing ⌥ to type doesn't flash a trail.
        let samplesBeforeTrail = 6

        while !Task.isCancelled {
            let elapsed = clock.now - origin
            let time = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            let active = triggerActive()
            let bounds = CGDisplayBounds(displayID)

            if let location = CGEvent(source: nil)?.location, bounds.width > 0, bounds.height > 0,
               bounds.contains(location) || !active {
                let local = CGPoint(x: location.x - bounds.minX, y: location.y - bounds.minY)
                let wasTracking = tracker.isTracking
                if let rect = tracker.update(position: local, time: time, active: active, screenSize: bounds.size) {
                    showingTrail = false
                    await onTrail([])
                    await onCircle(rect)
                } else if wasTracking, !tracker.isTracking {
                    if showingTrail { await onTrail([]) }
                    showingTrail = false
                } else if active, tracker.samples.count >= samplesBeforeTrail, time - lastTrail >= 1.0 / 30 {
                    lastTrail = time
                    showingTrail = true
                    await onTrail(tracker.samples.map {
                        CGPoint(x: $0.x / Double(bounds.width), y: $0.y / Double(bounds.height))
                    })
                }
            } else if tracker.isTracking {
                // Left the captured display while drawing.
                tracker.cancel()
                if showingTrail { await onTrail([]) }
                showingTrail = false
            }
            try? await Task.sleep(for: active || tracker.isTracking ? .milliseconds(16) : .milliseconds(60))
        }
        if showingTrail { await onTrail([]) }
    }
}
