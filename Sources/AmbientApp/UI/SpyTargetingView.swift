import SwiftUI

/// Full-screen, click-through overlay: target lock-on reticle around the
/// source text and the leader line to the card. The card itself lives in its
/// own small panel (`HUDCardHostView`) so it can accept clicks on hover.
///
/// Every animation is a pure function of the time since the message appeared,
/// so state changes never leave an animation half-finished.
struct SpyTargetingView: View {
    @ObservedObject var state: HUDState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !state.animating)) { timeline in
            let elapsed = reduceMotion ? 10 : timeline.date.timeIntervalSince(state.shownAt)
            ZStack(alignment: .topLeading) {
                if let message = state.message {
                    if let target = state.targetRect {
                        reticle(target: target, message: message, elapsed: elapsed)
                        leader(target: target, elapsed: elapsed)
                    }
                }
            }
            .frame(width: state.canvasSize.width, height: state.canvasSize.height, alignment: .topLeading)
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    // MARK: Reticle

    @ViewBuilder
    private func reticle(target: CGRect, message: HUDMessage, elapsed: TimeInterval) -> some View {
        let lock = ease(elapsed, start: 0, duration: 0.35)
        let frame = target.insetBy(dx: -8, dy: -6)
        let scale = 1.6 - 0.6 * lock
        let fade = max(0, 1 - ease(elapsed, start: 2.4, duration: 0.6) * 0.65)   // dims after the read starts

        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(SpyTheme.accent.opacity(0.18 * lock), style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                .frame(width: frame.width, height: frame.height)
            CornerBrackets(length: 9)
                .stroke(SpyTheme.accent, style: StrokeStyle(lineWidth: 1.8, lineCap: .square))
                .frame(width: frame.width, height: frame.height)
                .shadow(color: SpyTheme.accent.opacity(0.7), radius: 4)
            Text("\(HUDCodename.targetCode(for: message.id)) · \(lock >= 1 ? "LOCKED" : "ACQUIRING")")
                .font(SpyTheme.mono(8.5, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(SpyTheme.accent)
                .offset(y: -15)
                .opacity(lock >= 1 ? 1 : 0.6)
        }
        .scaleEffect(scale)
        .opacity(lock * fade)
        .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: Leader line

    @ViewBuilder
    private func leader(target: CGRect, elapsed: TimeInterval) -> some View {
        if let line = HUDGeometry.leaderLine(from: target.insetBy(dx: -8, dy: -6), to: state.cardRect) {
            let progress = ease(elapsed, start: 0.25, duration: 0.3)
            let end = CGPoint(x: line.start.x + (line.end.x - line.start.x) * progress,
                              y: line.start.y + (line.end.y - line.start.y) * progress)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: line.start)
                    path.addLine(to: end)
                }
                .stroke(SpyTheme.accent.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3], dashPhase: CGFloat(-elapsed * 20)))
                Circle()
                    .fill(SpyTheme.accent)
                    .frame(width: 5, height: 5)
                    .position(line.start)
                Circle()
                    .stroke(SpyTheme.accent, lineWidth: 1)
                    .frame(width: 7, height: 7)
                    .position(end)
                    .opacity(progress)
            }
            .frame(width: state.canvasSize.width, height: state.canvasSize.height, alignment: .topLeading)
            .opacity(min(1, progress * 2))
        }
    }

    // MARK: Helpers

    private func ease(_ elapsed: TimeInterval, start: TimeInterval, duration: TimeInterval) -> Double {
        HUDAnimation.ease(elapsed, start: start, duration: duration)
    }
}

enum HUDAnimation {
    /// Ease-out progress (0...1) of an animation starting at `start` lasting `duration`.
    static func ease(_ elapsed: TimeInterval, start: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        let t = min(max((elapsed - start) / duration, 0), 1)
        return 1 - pow(1 - t, 3)
    }
}
