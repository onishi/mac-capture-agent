import AppKit
import SwiftUI

/// Transparent, click-through, always-on-top panel that shows `HUDView`.
/// Hidden (ordered out) whenever there is nothing to show.
///
/// The panel never takes mouse events, so it can't block what is underneath.
/// Hovering it is still detected (by polling the pointer while visible): the
/// HUD stays up while hovered, and the hover counts as "interested" feedback.
@MainActor
final class OverlayWindowController {
    /// Called once per message when the pointer rests on the HUD.
    var onHover: ((HUDMessage) -> Void)?

    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView?>
    private let placement = HUDPlacement()
    private var lifecycleTask: Task<Void, Never>?
    private var generation = 0
    private var currentMessage: HUDMessage?
    private let fadeInDuration: TimeInterval = 0.3
    private let fadeOutDuration: TimeInterval = 0.4
    /// Time the HUD stays after the pointer leaves it.
    private let lingerAfterHover: TimeInterval = 1.5
    /// Pointer must rest this long on the HUD to count as interest.
    private let hoverThreshold: TimeInterval = 0.6
    private let pollInterval: Duration = .milliseconds(200)

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

    /// Shows `message` on `screen`, then fades it out.
    /// A message identical to the one currently on screen is ignored.
    func show(_ message: HUDMessage, on screen: NSScreen?, position: HUDPosition) {
        if panel.isVisible, message.isDuplicate(of: currentMessage) { return }
        guard let screen = screen ?? NSScreen.main else { return }
        currentMessage = message
        generation += 1
        let currentGeneration = generation

        hostingView.rootView = HUDView(message: message)
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let inset = HUDView.shadowMargin
        let cardSize = CGSize(width: max(1, fitting.width - inset * 2), height: max(1, fitting.height - inset * 2))
        let card = placement.frame(
            size: cardSize,
            anchor: message.anchor,
            position: position,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        )
        panel.setFrame(card.insetBy(dx: -inset, dy: -inset), display: true)

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            panel.animator().alphaValue = 1
        }
        Log.hud.info("HUD displayed")

        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            await self?.runLifecycle(message: message, generation: currentGeneration, cardFrame: card)
        }
    }

    func hide() {
        lifecycleTask?.cancel()
        fadeOut(generation: generation)
    }

    /// Keeps the HUD up for its display duration, extended while hovered.
    private func runLifecycle(message: HUDMessage, generation expected: Int, cardFrame: CGRect) async {
        let start = Date()
        var deadline = start.addingTimeInterval(message.displayDuration)
        var hoverStart: Date?
        var reportedHover = false

        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled, expected == generation else { return }
            let now = Date()
            if NSMouseInRect(NSEvent.mouseLocation, cardFrame, false) {
                let since = hoverStart ?? now
                hoverStart = since
                if !reportedHover, now.timeIntervalSince(since) >= hoverThreshold {
                    reportedHover = true
                    onHover?(message)
                }
                deadline = max(deadline, now.addingTimeInterval(lingerAfterHover))
            } else {
                hoverStart = nil
            }
            if now >= deadline { break }
        }
        guard !Task.isCancelled else { return }
        fadeOut(generation: expected)
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
                self.currentMessage = nil
            }
        })
    }
}
