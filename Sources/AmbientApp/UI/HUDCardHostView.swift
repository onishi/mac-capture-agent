import AppKit
import SwiftUI

/// Hosts the intel card inside its own panel. Plays the same time-based intro
/// as the targeting layer and shows the More actions while interactive.
struct HUDCardHostView: View {
    @ObservedObject var state: HUDState
    let bleed: CGFloat
    let onAction: (HUDAction) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !state.animating)) { timeline in
            if let message = state.message {
                card(message: message, elapsed: reduceMotion ? 10 : timeline.date.timeIntervalSince(state.shownAt), now: timeline.date)
                    .padding(bleed)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }

    private func card(message: HUDMessage, elapsed: TimeInterval, now: Date) -> some View {
        let anchored = state.targetRect != nil
        let unfold = HUDAnimation.ease(elapsed, start: anchored ? 0.3 : 0, duration: 0.25)
        let decodeStart = anchored ? 0.45 : 0.15
        let decode = reduceMotion ? 1 : DecodeEffect.progress(elapsed: elapsed - decodeStart, duration: 0.7)
        let sweepProgress = (elapsed - decodeStart) / 0.9
        let caret = Int(now.timeIntervalSinceReferenceDate * 2.5) % 2 == 0

        return HUDCardView(
            message: message,
            briefing: state.briefing,
            decodeProgress: decode,
            tick: Int(elapsed * 24),
            caretVisible: caret,
            sweep: (0...1).contains(sweepProgress) && !reduceMotion ? sweepProgress : nil,
            showsActions: state.interactive,
            onAction: onAction
        )
        .scaleEffect(x: 1, y: max(0.04, unfold), anchor: .top)
        .opacity(min(1, unfold * 1.5))
    }
}

/// Lets the first click on a non-key panel reach its buttons, so the HUD can
/// be used without activating the app or stealing keyboard focus.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
