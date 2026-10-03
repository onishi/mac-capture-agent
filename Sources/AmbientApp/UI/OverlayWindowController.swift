import AppKit
import SwiftUI

/// Transparent, click-through, always-on-top panel that shows `HUDView`.
/// Hidden (ordered out) whenever there is nothing to show.
@MainActor
final class OverlayWindowController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView?>
    private var hideTask: Task<Void, Never>?
    private var generation = 0
    private var lastMessage: HUDMessage?
    private let fadeInDuration: TimeInterval = 0.3
    private let fadeOutDuration: TimeInterval = 0.4
    private let screenMargin: CGFloat = 12

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: HUDView.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        hostingView = NSHostingView(rootView: nil)
        panel.contentView = hostingView
    }

    /// Shows `message` near the top-right corner of `screen`, then fades it out.
    /// A message identical to the one currently on screen is ignored.
    func show(_ message: HUDMessage, on screen: NSScreen?) {
        if panel.isVisible, message.isDuplicate(of: lastMessage) { return }
        lastMessage = message
        generation += 1
        let currentGeneration = generation

        hostingView.rootView = HUDView(message: message)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visible.maxX - size.width - screenMargin + HUDView.shadowMargin,
            y: visible.maxY - size.height - screenMargin + HUDView.shadowMargin
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            panel.animator().alphaValue = 1
        }
        Log.hud.info("HUD displayed")

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(message.displayDuration))
            guard !Task.isCancelled else { return }
            self?.fadeOut(generation: currentGeneration)
        }
    }

    func hide() {
        hideTask?.cancel()
        fadeOut(generation: generation)
    }

    private func fadeOut(generation expected: Int) {
        guard expected == generation, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                self.panel.orderOut(nil)
                self.hostingView.rootView = nil
            }
        })
    }
}
