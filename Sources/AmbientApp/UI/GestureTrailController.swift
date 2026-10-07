import AppKit
import SwiftUI

@MainActor
final class GestureTrailState: ObservableObject {
    /// Normalized, top-left-origin points of the stroke being drawn.
    @Published var points: [CGPoint] = []
    /// The circled area after recognition (briefly shown as a lock-on).
    @Published var locked: CGRect?
}

/// Draws the ⌥-circle stroke and a short lock-on on a click-through panel
/// (LOCAL_AI.md LA-60). Excluded from capture like the other HUD panels.
@MainActor
final class GestureTrailController {
    private let panel: NSPanel
    private let state = GestureTrailState()
    private var hideTask: Task<Void, Never>?

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
        panel.contentView = NSHostingView(rootView: GestureTrailView(state: state))
    }

    func update(_ points: [CGPoint], on screen: NSScreen?) {
        guard !points.isEmpty else {
            state.points = []
            if state.locked == nil { panel.orderOut(nil) }
            return
        }
        guard let screen = screen ?? NSScreen.main else { return }
        hideTask?.cancel()
        state.locked = nil
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        state.points = points
        panel.orderFrontRegardless()
    }

    /// Brief lock-on brackets around the circled area while it is analyzed.
    func lock(_ rect: CGRect, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
        state.points = []
        state.locked = rect
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.state.locked = nil
            self?.panel.orderOut(nil)
        }
    }
}

private struct GestureTrailView: View {
    @ObservedObject var state: GestureTrailState

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                if state.points.count > 1 {
                    Path { path in
                        path.addLines(state.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    }
                    .stroke(SpyTheme.accent.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: SpyTheme.accent.opacity(0.6), radius: 6)
                }
                if let locked = state.locked {
                    let frame = CGRect(x: locked.minX * size.width, y: locked.minY * size.height,
                                       width: locked.width * size.width, height: locked.height * size.height)
                    CornerBrackets(length: SpyTheme.cornerTick * 1.6)
                        .stroke(SpyTheme.accent, lineWidth: 1.5)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .shadow(color: SpyTheme.accent.opacity(0.6), radius: 4)
                    Text("ACQUIRING")
                        .font(SpyTheme.mono(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(SpyTheme.accent)
                        .position(x: frame.minX + 40, y: max(8, frame.minY - 10))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}
