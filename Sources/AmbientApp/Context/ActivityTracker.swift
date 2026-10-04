import AppKit
import CoreGraphics

/// Tracks what is in front (page = URL or app + window title) to record
/// reading activity, score automatic bookmarks and group work sessions.
/// Samples every 2 s on the main thread; records titles and URLs only —
/// never screen content. Honors the privacy policy and pauses with the app.
@MainActor
final class ActivityTracker {
    struct Configuration: Equatable, Sendable {
        var enabled: Bool
        var readBrowserURLs: Bool
        var privacyPolicy: PrivacyPolicy
        var targetLanguage: String
    }

    let page = PageContext()
    private let store: IntelStore
    private let foreground: ForegroundContextProvider
    private let namer: (any SessionNaming)?
    private let urls = BrowserURLProvider()
    private let clusterer = WorkSessionClusterer()
    private var configuration: Configuration?
    private var timer: Timer?

    private struct CurrentPage {
        let id = UUID()
        let key: PageKey
        let application: String?
        let bundleIdentifier: String?
        let title: String?
        let url: URL?
        let start: Date
        var lastActive: Date
        var activity = PageActivity()
    }

    private var current: CurrentPage?
    private var lastTitleKey: String?
    private var lastURL: URL?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var lastMouse: NSPoint?
    private var stillTicks = 0
    private var lastClustering = Date.distantPast

    private let interval: TimeInterval = 2
    private let idleThreshold: TimeInterval = 120
    private let minimumVisit: TimeInterval = 5
    private let clusteringInterval: TimeInterval = 5 * 60

    init(store: IntelStore, foreground: ForegroundContextProvider, namer: (any SessionNaming)?) {
        self.store = store
        self.foreground = foreground
        self.namer = namer
    }

    /// Starts sampling, or applies a new configuration (stopping when disabled).
    func start(_ configuration: Configuration) {
        self.configuration = configuration
        guard configuration.enabled else {
            stop()
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard timer != nil || current != nil else { return }
        timer?.invalidate()
        timer = nil
        flush(at: Date())
        page.update(url: nil)
        regroupSessions(force: true)
    }

    /// Called when a HUD was shown for the page in front.
    func noteIntelShown() {
        current?.activity.intelShown += 1
    }

    // MARK: Sampling

    private func tick() {
        guard let configuration, configuration.enabled else { return }
        let now = Date()
        let app = foreground.current
        let title = foreground.windowTitle(for: app.processIdentifier)

        guard configuration.privacyPolicy.allowsAnalysis(bundleIdentifier: app.bundleIdentifier, windowTitle: title),
              app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            flush(at: now)
            page.update(url: nil)
            return
        }

        // Ask the browser for its URL only when the page (app + title) changed.
        let titleKey = "\(app.bundleIdentifier ?? "")|\(title ?? "")"
        if titleKey != lastTitleKey {
            lastTitleKey = titleKey
            lastURL = configuration.readBrowserURLs ? urls.currentURL(for: app.bundleIdentifier) : nil
        }
        page.update(url: lastURL)
        let key = PageKey(bundleIdentifier: app.bundleIdentifier, windowTitle: title, url: lastURL)

        if current?.key != key {
            flush(at: now)
            current = CurrentPage(key: key, application: app.appName, bundleIdentifier: app.bundleIdentifier,
                                  title: title, url: lastURL, start: now, lastActive: now)
        } else if Self.idleSeconds() < idleThreshold {
            current?.activity.focusSeconds += interval
            current?.lastActive = now
        }

        let changeCount = NSPasteboard.general.changeCount
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            current?.activity.copies += 1
        }

        let mouse = NSEvent.mouseLocation
        if let last = lastMouse, hypot(mouse.x - last.x, mouse.y - last.y) < 3 {
            stillTicks += 1
            if stillTicks == 1 { current?.activity.pointerDwells += 1 }
        } else {
            stillTicks = 0
        }
        lastMouse = mouse

        if now.timeIntervalSince(lastClustering) >= clusteringInterval {
            regroupSessions(force: false)
        }
    }

    /// Persists the page that just left the front, and bookmarks it if important.
    private func flush(at now: Date) {
        guard let page = current else { return }
        current = nil
        guard page.activity.focusSeconds >= minimumVisit else { return }
        let visit = PageVisit(id: page.id, key: page.key, application: page.application, bundleIdentifier: page.bundleIdentifier,
                              title: page.title, url: page.url, start: page.start,
                              end: page.start.addingTimeInterval(page.activity.focusSeconds))
        let store = self.store
        var activity = page.activity
        Task {
            await store.recordPageVisit(visit)
            activity.revisits = await store.visitCount(visit.key, since: now.addingTimeInterval(-7 * 24 * 3600), excluding: visit.id)
            let score = BookmarkScorer.score(activity)
            if score.isBookmark {
                await store.saveBookmark(observationID: visit.id, score: score)
                Log.app.info("Page bookmarked (score \(score.value, format: .fixed(precision: 2)))")
            }
        }
    }

    /// Re-clusters the last 24 h of visits into sessions and names new ones.
    private func regroupSessions(force: Bool) {
        lastClustering = Date()
        guard let configuration else { return }
        let store = self.store
        let clusterer = self.clusterer
        let namer = self.namer
        Task.detached(priority: .utility) {
            let visits = await store.pageVisits(since: Date().addingTimeInterval(-24 * 3600))
            let drafts = clusterer.cluster(visits).filter { $0.activeDuration >= 5 * 60 }
            var named: [(draft: WorkSessionDraft, name: String)] = []
            var modelCalls = 0
            for draft in drafts {
                if let existing = await store.sessionName(draft.id) {
                    named.append((draft, existing))
                    continue
                }
                var name: String?
                if let namer, namer.isAvailable, modelCalls < 2 {
                    modelCalls += 1
                    let titles = Array(draft.visits.compactMap(\.title).prefix(12))
                    name = (try? await namer.nameSession(titles: titles, applications: draft.applications,
                                                         targetLanguage: configuration.targetLanguage)).flatMap(SessionNameSanitizer.sanitize)
                }
                named.append((draft, name ?? draft.fallbackName))
            }
            if !named.isEmpty {
                await store.saveSessions(named)
            }
        }
    }

    private static func idleSeconds() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }
}
