import AppKit
import SwiftUI
import Translation

/// Serializes translation requests through SwiftUI's `.translationTask`
/// modifier, which is the only way to obtain a `TranslationSession` on macOS 15.
///
/// Every request has a timeout so that a session which never starts can not
/// stall the analysis pipeline.
@MainActor
final class TranslationBridge: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?

    private struct Job {
        let id: UUID
        let text: String
        let source: Locale.Language
        let target: Locale.Language
        let continuation: CheckedContinuation<String, Error>
    }

    private var queue: [Job] = []
    private var activeJobID: UUID?
    private var activePair: (source: Locale.Language, target: Locale.Language)?
    private let timeout: Duration = .seconds(8)

    nonisolated func translate(_ text: String, source: Locale.Language, target: Locale.Language) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.enqueue(Job(id: UUID(), text: text, source: source, target: target, continuation: continuation))
            }
        }
    }

    private func enqueue(_ job: Job) {
        queue.append(job)
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.timeout)
            self.fail(jobID: job.id, with: TranslationProviderError.timedOut)
        }
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard activeJobID == nil, let job = queue.first else { return }
        activeJobID = job.id
        if let pair = activePair, pair.source == job.source, pair.target == job.target, configuration != nil {
            // Same languages: re-trigger the existing task.
            configuration?.invalidate()
        } else {
            activePair = (job.source, job.target)
            configuration = TranslationSession.Configuration(source: job.source, target: job.target)
        }
    }

    /// Called from `.translationTask` whenever the configuration changes or is invalidated.
    func run(with session: TranslationSession) async {
        guard let jobID = activeJobID, let job = queue.first(where: { $0.id == jobID }) else { return }
        do {
            let response = try await session.translate(job.text)
            complete(jobID: jobID, with: .success(response.targetText))
        } catch {
            complete(jobID: jobID, with: .failure(error))
        }
    }

    private func fail(jobID: UUID, with error: Error) {
        complete(jobID: jobID, with: .failure(error))
    }

    /// Resumes a job exactly once (whichever comes first: result or timeout).
    private func complete(jobID: UUID, with result: Result<String, Error>) {
        guard let index = queue.firstIndex(where: { $0.id == jobID }) else { return }
        let job = queue.remove(at: index)
        job.continuation.resume(with: result)
        if activeJobID == jobID {
            activeJobID = nil
            startNextIfNeeded()
        }
    }
}

/// Invisible view that hosts the `.translationTask` modifier.
struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(bridge.configuration) { session in
                await bridge.run(with: session)
            }
    }
}

/// A 1×1 transparent, click-through window that keeps `TranslationBridgeView`
/// in a live view hierarchy (required for `.translationTask` to run).
@MainActor
final class TranslationHostWindow {
    private let window: NSPanel

    init(bridge: TranslationBridge) {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: TranslationBridgeView(bridge: bridge))
    }

    func show() {
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.minX, y: screen.frame.minY))
        }
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }
}
