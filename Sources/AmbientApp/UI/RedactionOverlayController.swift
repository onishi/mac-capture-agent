import AppKit
import SwiftUI

/// Experimental: while the screen is shared, covers detected secrets with
/// opaque boxes. Meeting apps capture this window (our own capture excludes
/// it), so viewers see the box instead of the secret. Boxes clear by
/// themselves after a few seconds unless refreshed.
@MainActor
final class RedactionOverlayController {
    private let panel: NSPanel
    private let model = RedactionModel()
    private var clearTask: Task<Void, Never>?

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
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: RedactionView(model: model))
    }

    func cover(_ rects: [CGRect], on screen: NSScreen?) {
        guard !rects.isEmpty, let screen = screen ?? NSScreen.main else { clear(); return }
        panel.setFrame(screen.frame, display: false)
        model.canvasSize = screen.frame.size
        model.rects = rects
        panel.orderFrontRegardless()
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func clear() {
        clearTask?.cancel()
        model.rects = []
        panel.orderOut(nil)
    }
}

@MainActor
private final class RedactionModel: ObservableObject {
    @Published var rects: [CGRect] = []
    @Published var canvasSize: CGSize = .zero
}

private struct RedactionView: View {
    @ObservedObject var model: RedactionModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.rects.enumerated()), id: \.offset) { _, rect in
                let frame = CGRect(x: rect.minX * model.canvasSize.width, y: rect.minY * model.canvasSize.height,
                                   width: rect.width * model.canvasSize.width, height: rect.height * model.canvasSize.height)
                    .insetBy(dx: -4, dy: -3)
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        Text("■ REDACTED")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(SpyTheme.alert)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: model.canvasSize.width, height: model.canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
