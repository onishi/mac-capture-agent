import AppKit
import SwiftUI

/// Developer overlay: shows what the pipeline looked at and decided.
/// Geometry, scores, counts and timings only — never recognized text.
@MainActor
final class DebugOverlayState: ObservableObject {
    @Published var diagnostics = PipelineDiagnostics()
    @Published var counters = PipelineCounters()
    @Published var updatedAt = Date.distantPast
    @Published var canvasSize: CGSize = .zero
}

@MainActor
final class DebugOverlayController {
    private let panel: NSPanel
    private let state = DebugOverlayState()
    private var screen: NSScreen?

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
        panel.contentView = NSHostingView(rootView: DebugOverlayView(state: state))
    }

    func update(_ diagnostics: PipelineDiagnostics, counters: PipelineCounters, on screen: NSScreen?) {
        guard let screen = screen ?? NSScreen.main else { return }
        if self.screen != screen || !panel.isVisible {
            self.screen = screen
            panel.setFrame(screen.frame, display: false)
            state.canvasSize = screen.frame.size
            panel.orderFrontRegardless()
        }
        // Keep the last analysis on screen while only change regions update.
        if diagnostics.hasAnalysis {
            state.diagnostics = diagnostics
        } else {
            state.diagnostics.changedRegions = diagnostics.changedRegions
            state.diagnostics.timings["detect"] = diagnostics.timings["detect"]
        }
        state.counters = counters
        state.updatedAt = Date()
    }

    func hide() {
        panel.orderOut(nil)
        state.diagnostics = PipelineDiagnostics()
    }
}

struct DebugOverlayView: View {
    @ObservedObject var state: DebugOverlayState

    private let changeColor = Color(red: 1, green: 0.25, blue: 0.85)
    private let ocrColor = Color(red: 1, green: 0.85, blue: 0.2)
    private let selectedColor = Color(red: 0.3, green: 1, blue: 0.45)
    private let rejectedColor = Color(red: 1, green: 0.35, blue: 0.35)

    var body: some View {
        let size = state.canvasSize
        ZStack(alignment: .topLeading) {
            ForEach(Array(state.diagnostics.changedRegions.enumerated()), id: \.offset) { _, rect in
                box(rect, in: size, color: changeColor, dash: [2, 3], width: 1)
            }
            ForEach(Array(state.diagnostics.analyzedRegions.enumerated()), id: \.offset) { _, rect in
                box(rect, in: size, color: ocrColor, dash: [], width: 1)
            }
            ForEach(Array(state.diagnostics.candidates.enumerated()), id: \.offset) { _, candidate in
                if let region = candidate.region {
                    candidateBox(candidate, region: region, in: size)
                }
            }
            statusPanel
                .padding(.top, 34)
                .padding(.leading, 12)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
    }

    private func viewRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height, width: rect.width * size.width, height: rect.height * size.height)
    }

    private func box(_ rect: CGRect, in size: CGSize, color: Color, dash: [CGFloat], width: CGFloat) -> some View {
        let frame = viewRect(rect, in: size)
        return Rectangle()
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: width, dash: dash))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }

    private func candidateBox(_ candidate: PipelineDiagnostics.Candidate, region: CGRect, in size: CGSize) -> some View {
        let frame = viewRect(region, in: size)
        let color = candidate.selected && !candidate.suppressedByCooldown ? selectedColor : rejectedColor
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: frame.width, height: frame.height)
            Text(candidate.label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 3)
                .background(color)
                .offset(y: -13)
        }
        .offset(x: frame.minX, y: frame.minY)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("◢ DEBUG // PIPELINE")
                .foregroundStyle(SpyTheme.accent)
            Text(state.counters.summary)
            Text("LINES \(state.diagnostics.textLineCount) · BLOCKS \(state.diagnostics.textBlockCount) · CANDIDATES \(state.diagnostics.candidates.count)")
            Text(PipelineCounters.formatTimings(state.diagnostics.timings))
            HStack(spacing: 10) {
                legend("CHANGE", changeColor)
                legend("OCR", ocrColor)
                legend("SHOWN", selectedColor)
                legend("REJECTED", rejectedColor)
            }
        }
        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.9))
        .padding(8)
        .background(Color.black.opacity(0.72))
        .overlay(Rectangle().stroke(SpyTheme.accentDim, lineWidth: 0.75))
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Rectangle().fill(color).frame(width: 8, height: 8)
            Text(title)
        }
    }
}
