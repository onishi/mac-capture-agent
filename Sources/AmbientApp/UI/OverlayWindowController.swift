import AppKit
import SwiftUI

/// Transparent, click-through, always-on-top panel covering the target screen.
/// It draws the spy-style HUD (`SpyHUDView`) and is ordered out whenever there
/// is nothing to show.
///
/// The panel never takes mouse events, so it can't block what is underneath.
/// Hovering the card is still detected (by polling the pointer while visible):
/// the HUD stays up while hovered, and the hover counts as "interested" feedback.
@MainActor
final class OverlayWindowController {
    /// Called once per message when the pointer rests on the card.
    var onHover: ((HUDMessage) -> Void)?

    private let panel: NSPanel
    private let state = HUDState()
    private let hostingView: NSHostingView<SpyHUDView>
    private let measuringView = NSHostingView<HUDCardView?>(rootView: nil)
    private let placement = HUDPlacement()
    private var lifecycleTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var generation = 0
    private var currentMessage: HUDMessage?
    private var currentScreen: NSScreen?
    private var currentPosition: HUDPosition = .nearTarget
    /// Card frame in AppKit screen coordinates, for hover detection.
    private var cardScreenFrame: CGRect = .zero
    private var deadline = Date()

    private let fadeInDuration: TimeInterval = 0.3
    private let fadeOutDuration: TimeInterval = 0.4
    private let introDuration: TimeInterval = 1.8
    /// Time the HUD stays after the pointer leaves it.
    private let lingerAfterHover: TimeInterval = 1.5
    /// Pointer must rest this long on the card to count as interest.
    private let hoverThreshold: TimeInterval = 0.6
    /// Extra reading time once a briefing arrives.
    private let briefingReadTime: TimeInterval = 2.5
    private let pollInterval: Duration = .milliseconds(200)

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
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

        hostingView = NSHostingView(rootView: SpyHUDView(state: state))
        panel.contentView = hostingView
    }

    // MARK: Public

    /// Shows `message` on `screen`, then fades it out.
    /// A message identical to the one currently on screen is ignored.
    func show(_ message: HUDMessage, on screen: NSScreen?, position: HUDPosition, briefingPending: Bool) {
        if panel.isVisible, message.isDuplicate(of: currentMessage) { return }
        guard let screen = screen ?? NSScreen.main else { return }
        currentMessage = message
        currentScreen = screen
        currentPosition = position
        generation += 1
        let currentGeneration = generation

        panel.setFrame(screen.frame, display: false)
        state.canvasSize = screen.frame.size
        state.message = message
        state.briefing = briefingPending ? .pending : .none
        state.shownAt = Date()
        layout()
        startAnimating(keepRunning: briefingPending)

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            panel.animator().alphaValue = 1
        }
        Log.hud.info("HUD displayed")

        deadline = Date().addingTimeInterval(message.displayDuration(withBriefing: briefingPending))
        lifecycleTask?.cancel()
        lifecycleTask = Task { [weak self] in
            await self?.runLifecycle(message: message, generation: currentGeneration)
        }
    }

    /// Fills in (or removes) the briefing line of the message on screen.
    func updateBriefing(_ text: String?, for messageID: UUID) {
        guard state.message?.id == messageID, state.briefing == .pending else { return }
        if let text {
            state.briefing = .ready(text)
            deadline = max(deadline, Date().addingTimeInterval(briefingReadTime))
            Log.hud.debug("Briefing displayed")
        } else {
            state.briefing = .none
        }
        layout()
        startAnimating(keepRunning: false)
    }

    func hide() {
        lifecycleTask?.cancel()
        fadeOut(generation: generation)
    }

    // MARK: Layout

    private func layout() {
        guard let message = state.message, let screen = currentScreen else { return }
        measuringView.rootView = HUDCardView(message: message, briefing: state.briefing)
        measuringView.layoutSubtreeIfNeeded()
        let size = measuringView.fittingSize
        let bleed = SpyTheme.cornerTick  // room for the brackets and glow
        let card = placement.frame(
            size: CGSize(width: size.width + bleed, height: size.height + bleed),
            anchor: currentPosition == .nearTarget ? message.anchor : nil,
            position: currentPosition,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        ).insetBy(dx: bleed / 2, dy: bleed / 2)
        cardScreenFrame = card
        state.cardRect = HUDGeometry.viewRect(fromScreenRect: card, screenFrame: screen.frame)
        if currentPosition == .nearTarget, let anchor = message.anchor {
            let target = HUDPlacement.screenRect(forAnchor: anchor, screenFrame: screen.frame)
            state.targetRect = HUDGeometry.viewRect(fromScreenRect: target, screenFrame: screen.frame)
        } else {
            state.targetRect = nil
        }
    }

    /// Runs the timeline for the intro (and while a briefing is pending), then pauses it.
    private func startAnimating(keepRunning: Bool) {
        state.animating = true
        animationTask?.cancel()
        guard !keepRunning else { return }
        let remaining = max(0.6, introDuration - Date().timeIntervalSince(state.shownAt))
        animationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self, self.state.briefing != .pending else { return }
            self.state.animating = false
        }
    }

    // MARK: Lifecycle

    /// Keeps the HUD up until its deadline, extended while hovered.
    private func runLifecycle(message: HUDMessage, generation expected: Int) async {
        var hoverStart: Date?
        var reportedHover = false

        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled, expected == generation else { return }
            let now = Date()
            if NSMouseInRect(NSEvent.mouseLocation, cardScreenFrame, false) {
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
                self.animationTask?.cancel()
                self.state.animating = false
                self.state.message = nil
                self.state.briefing = .none
                self.currentMessage = nil
            }
        })
    }
}
