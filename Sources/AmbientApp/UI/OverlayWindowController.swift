import AppKit
import SwiftUI

/// Presents the spy-style HUD with two panels:
/// - a full-screen, always click-through panel for the reticle and leader line;
/// - a card-sized panel for the intel card, which becomes clickable (and shows
///   its More actions) only after the pointer rests on it.
///
/// Both are ordered out whenever there is nothing to show, and neither ever
/// becomes key, so the user's app keeps keyboard focus.
@MainActor
final class OverlayWindowController {
    /// Called once per message when the pointer rests on the card (More opened).
    var onHover: ((HUDMessage) -> Void)?
    /// Called when one of the card's More actions is used.
    var onAction: ((HUDAction, HUDMessage) -> Void)?

    private let targetingPanel: NSPanel
    private let cardPanel: NSPanel
    private let state = HUDState()
    private let measuringView = NSHostingView<HUDCardView?>(rootView: nil)
    private let placement = HUDPlacement()
    private var lifecycleTask: Task<Void, Never>?
    private var animationTask: Task<Void, Never>?
    private var generation = 0
    private var currentMessage: HUDMessage?
    private var currentScreen: NSScreen?
    private var currentPosition: HUDPosition = .nearTarget
    /// Card frame (without bleed) in AppKit screen coordinates.
    private var cardScreenFrame: CGRect = .zero
    /// Card frame before the More actions expanded it.
    private var collapsedCardFrame: CGRect = .zero
    private var deadline = Date()

    private let bleed: CGFloat = 16          // room for corner brackets and glow
    private let fadeInDuration: TimeInterval = 0.3
    private let fadeOutDuration: TimeInterval = 0.4
    private let introDuration: TimeInterval = 1.8
    /// Time the HUD stays after the pointer leaves it.
    private let lingerAfterHover: TimeInterval = 1.5
    /// Pointer must rest this long on the card to open its actions.
    private let hoverThreshold: TimeInterval = 0.6
    /// Pointer must be away this long before the actions close again.
    private let leaveGrace: TimeInterval = 0.4
    private let briefingReadTime: TimeInterval = 2.5
    private let pollInterval: Duration = .milliseconds(150)

    init() {
        targetingPanel = Self.makePanel()
        cardPanel = Self.makePanel()
        targetingPanel.contentView = NSHostingView(rootView: SpyTargetingView(state: state))
        cardPanel.contentView = FirstMouseHostingView(rootView: HUDCardHostView(state: state, bleed: bleed) { [weak self] action in
            self?.handle(action)
        })
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
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
        panel.becomesKeyOnlyIfNeeded = true
        panel.alphaValue = 0
        return panel
    }

    private var panels: [NSPanel] { [targetingPanel, cardPanel] }

    // MARK: Public

    /// Shows `message` on `screen`, then fades it out.
    /// A message identical to the one currently on screen is ignored.
    func show(_ message: HUDMessage, on screen: NSScreen?, position: HUDPosition, briefingPending: Bool) {
        if cardPanel.isVisible, message.isDuplicate(of: currentMessage) { return }
        guard let screen = screen ?? NSScreen.main else { return }
        currentMessage = message
        currentScreen = screen
        currentPosition = position
        generation += 1
        let currentGeneration = generation

        targetingPanel.setFrame(screen.frame, display: false)
        state.canvasSize = screen.frame.size
        state.message = message
        state.briefing = briefingPending ? .pending : .none
        state.shownAt = Date()
        setInteractive(false)
        layout()
        startAnimating(keepRunning: briefingPending)

        for panel in panels {
            if !panel.isVisible { panel.alphaValue = 0 }
        }
        targetingPanel.orderFrontRegardless()
        cardPanel.orderFrontRegardless()   // above the targeting layer
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeInDuration
            for panel in panels { panel.animator().alphaValue = 1 }
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
        if state.interactive {
            resizeInteractiveCard()
        } else {
            layout()
        }
        startAnimating(keepRunning: false)
    }

    func hide() {
        lifecycleTask?.cancel()
        fadeOut(generation: generation)
    }

    // MARK: Layout

    private func measureCard(_ message: HUDMessage, actions: Bool) -> CGSize {
        measuringView.rootView = HUDCardView(message: message, briefing: state.briefing, showsActions: actions)
        measuringView.layoutSubtreeIfNeeded()
        return measuringView.fittingSize
    }

    /// Places the collapsed card (and the target reticle) on screen.
    private func layout() {
        guard let message = state.message, let screen = currentScreen else { return }
        let size = measureCard(message, actions: false)
        let card = placement.frame(
            size: CGSize(width: size.width + bleed, height: size.height + bleed),
            anchor: currentPosition == .nearTarget ? message.anchor : nil,
            position: currentPosition,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame
        ).insetBy(dx: bleed / 2, dy: bleed / 2)
        collapsedCardFrame = card
        applyCardFrame(card)
        if currentPosition == .nearTarget, let anchor = message.anchor {
            let target = HUDPlacement.screenRect(forAnchor: anchor, screenFrame: screen.frame)
            state.targetRect = HUDGeometry.viewRect(fromScreenRect: target, screenFrame: screen.frame)
        } else {
            state.targetRect = nil
        }
    }

    private func applyCardFrame(_ card: CGRect) {
        guard let screen = currentScreen else { return }
        cardScreenFrame = card
        cardPanel.setFrame(card.insetBy(dx: -bleed, dy: -bleed), display: true)
        state.cardRect = HUDGeometry.viewRect(fromScreenRect: card, screenFrame: screen.frame)
    }

    /// Expands the card downward (top edge fixed) to make room for the actions.
    private func resizeInteractiveCard() {
        guard let message = state.message, let screen = currentScreen else { return }
        let collapsed = measureCard(message, actions: false)
        let expanded = measureCard(message, actions: true)
        let base = CGRect(x: collapsedCardFrame.minX, y: collapsedCardFrame.maxY - collapsed.height,
                          width: collapsedCardFrame.width, height: collapsed.height)
        applyCardFrame(placement.grow(base, byHeight: max(0, expanded.height - collapsed.height), within: screen.visibleFrame))
    }

    private func setInteractive(_ interactive: Bool) {
        guard state.interactive != interactive else { return }
        state.interactive = interactive
        cardPanel.ignoresMouseEvents = !interactive
        if interactive {
            resizeInteractiveCard()
        } else {
            applyCardFrame(collapsedCardFrame)
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

    // MARK: Actions

    private func handle(_ action: HUDAction) {
        guard let message = currentMessage else { return }
        onAction?(action, message)
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.detail, forType: .string)
            deadline = max(deadline, Date().addingTimeInterval(1))
        case .openArchive, .notUseful, .skipLanguage, .close:
            hide()
        }
    }

    // MARK: Lifecycle

    /// Keeps the HUD up until its deadline, extended while hovered, and opens
    /// the actions when the pointer rests on the card.
    private func runLifecycle(message: HUDMessage, generation expected: Int) async {
        var hoverStart: Date?
        var leftAt: Date?
        var reportedHover = false

        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled, expected == generation else { return }
            let now = Date()
            if NSMouseInRect(NSEvent.mouseLocation, cardScreenFrame, false) {
                leftAt = nil
                let since = hoverStart ?? now
                hoverStart = since
                if !state.interactive, now.timeIntervalSince(since) >= hoverThreshold {
                    setInteractive(true)
                    if !reportedHover {
                        reportedHover = true
                        onHover?(message)
                    }
                }
                deadline = max(deadline, now.addingTimeInterval(lingerAfterHover))
            } else {
                hoverStart = nil
                if state.interactive {
                    let since = leftAt ?? now
                    leftAt = since
                    if now.timeIntervalSince(since) >= leaveGrace {
                        setInteractive(false)
                    }
                }
            }
            if now >= deadline, !state.interactive { break }
        }
        guard !Task.isCancelled else { return }
        fadeOut(generation: expected)
    }

    private func fadeOut(generation expected: Int) {
        guard expected == generation, cardPanel.isVisible || targetingPanel.isVisible else { return }
        setInteractive(false)
        cardPanel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fadeOutDuration
            for panel in panels { panel.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == expected else { return }
                for panel in self.panels { panel.orderOut(nil) }
                self.animationTask?.cancel()
                self.state.animating = false
                self.state.message = nil
                self.state.briefing = .none
                self.currentMessage = nil
            }
        })
    }
}
