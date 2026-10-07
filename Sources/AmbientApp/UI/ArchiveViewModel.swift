import AppKit
import Combine

enum ArchiveTab: String, CaseIterable {
    case records = "RECORDS"
    case sessions = "SESSIONS"
    case today = "TODAY"
    case aiLog = "AI LOG"
}

@MainActor
final class ArchiveViewModel: ObservableObject {
    @Published var tab: ArchiveTab = .records {
        didSet {
            switch tab {
            case .records: refresh()
            case .sessions, .today: refreshSessions()
            case .aiLog: refreshAILog()
            }
        }
    }
    /// The on-device LLM's answers, newest first (SPEC AL-1).
    @Published private(set) var aiAnswers: [AIAnswerRecord] = []
    @Published private(set) var sessions: [WorkSessionRecord] = []
    @Published private(set) var themes: [DailySummary.Theme] = []
    @Published var query = ""
    @Published private(set) var results: [MemorySearchResult] = []
    @Published private(set) var totalRecords = 0
    @Published private(set) var copiedID: UUID?
    @Published private(set) var isSearching = false

    let retentionDays: () -> Int
    let memoryEnabled: () -> Bool
    private let store: IntelStore
    private let onOpen: (VisualMemoryEntry) -> Void
    private var queryObservation: AnyCancellable?
    private var searchTask: Task<Void, Never>?

    init(
        store: IntelStore,
        retentionDays: @escaping () -> Int,
        memoryEnabled: @escaping () -> Bool,
        onOpen: @escaping (VisualMemoryEntry) -> Void
    ) {
        self.store = store
        self.retentionDays = retentionDays
        self.memoryEnabled = memoryEnabled
        self.onOpen = onOpen
        queryObservation = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.tab == .aiLog { self.refreshAILog() } else { self.refresh() }
            }
    }

    func refresh() {
        searchTask?.cancel()
        let query = self.query
        let store = self.store
        isSearching = true
        searchTask = Task { [weak self] in
            let results = await store.search(query, limit: 50)
            let total = await store.count()
            guard !Task.isCancelled, let self else { return }
            self.results = results
            self.totalRecords = total
            self.isSearching = false
        }
    }

    /// Copies the translation and tells personalization the user went looking for it.
    func open(_ entry: VisualMemoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.translation, forType: .string)
        copiedID = entry.id
        onOpen(entry)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.copiedID == entry.id { self?.copiedID = nil }
        }
    }

    func refreshSessions() {
        let store = self.store
        Task { [weak self] in
            let now = Date()
            let week = await store.sessions(since: now.addingTimeInterval(-7 * 24 * 3600))
            let today = week.filter { $0.end >= Calendar.current.startOfDay(for: now) }
            let themes = DailySummary.themes(today.map { (name: $0.title ?? "Session", activeDuration: $0.activeSeconds) })
            guard let self else { return }
            self.sessions = week
            self.themes = themes
        }
    }

    func refreshAILog() {
        let store = self.store
        let query = self.query
        Task { [weak self] in
            let answers = await store.aiAnswers(matching: query, limit: 300)
            self?.aiAnswers = answers
        }
    }

    /// Copies the answer text.
    func copy(_ answer: AIAnswerRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer.answer, forType: .string)
        copiedID = answer.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if self?.copiedID == answer.id { self?.copiedID = nil }
        }
    }

    func clearAILog() {
        let store = self.store
        Task { [weak self] in
            await store.removeAIAnswers()
            self?.refreshAILog()
        }
    }

    func openPage(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func purge() {
        let store = self.store
        Task { [weak self] in
            await store.removeAll()
            self?.refresh()
            self?.refreshAILog()
        }
    }
}
