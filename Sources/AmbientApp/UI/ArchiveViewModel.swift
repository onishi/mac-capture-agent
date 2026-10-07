import AppKit
import Combine

enum ArchiveTab: String, CaseIterable {
    case records = "RECORDS"
    case sessions = "SESSIONS"
    case today = "TODAY"
    case aiLog = "AI LOG"
}

/// The answer to a question asked in the archive (LA-30).
struct ArchiveAnswer: Equatable {
    var question: String
    var text: String?
    var isLoading: Bool
    /// The records the answer cites (1-based numbers into `evidence`).
    var cited: [VisualMemoryEntry] = []
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

    @Published private(set) var answer: ArchiveAnswer?

    let retentionDays: () -> Int
    let memoryEnabled: () -> Bool
    private let store: IntelStore
    private let onOpen: (VisualMemoryEntry) -> Void
    private let answerer: (any ArchiveAnswering)?
    private let askingEnabled: () -> Bool
    private let aiLogEnabled: () -> Bool
    private let targetLanguage: () -> String
    private var askTask: Task<Void, Never>?

    /// Questions ("…?") can be answered from the archive by the on-device model.
    var canAsk: Bool { askingEnabled() && answerer?.isAvailable == true }
    private var queryObservation: AnyCancellable?
    private var searchTask: Task<Void, Never>?

    init(
        store: IntelStore,
        retentionDays: @escaping () -> Int,
        memoryEnabled: @escaping () -> Bool,
        answerer: (any ArchiveAnswering)? = nil,
        askingEnabled: @escaping () -> Bool = { false },
        aiLogEnabled: @escaping () -> Bool = { false },
        targetLanguage: @escaping () -> String = { "ja" },
        onOpen: @escaping (VisualMemoryEntry) -> Void
    ) {
        self.store = store
        self.retentionDays = retentionDays
        self.memoryEnabled = memoryEnabled
        self.answerer = answerer
        self.askingEnabled = askingEnabled
        self.aiLogEnabled = aiLogEnabled
        self.targetLanguage = targetLanguage
        self.onOpen = onOpen
        queryObservation = $query
            .removeDuplicates()
            .debounce(for: .milliseconds(220), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if let answer = self.answer, ArchiveQuestion.question(from: self.query) != answer.question {
                    self.dismissAnswer()
                }
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

    /// Return in the query field: a question ("…?") is answered from the
    /// archive by the on-device model, using only the top search results.
    func submit() {
        guard tab == .records, ArchiveQuestion.isQuestion(query), canAsk, let answerer else { return }
        let question = ArchiveQuestion.question(from: query)
        let store = self.store
        let language = targetLanguage()
        let logging = aiLogEnabled()
        askTask?.cancel()
        answer = ArchiveAnswer(question: question, text: nil, isLoading: true)
        askTask = Task { [weak self] in
            let started = Date()
            let entries = await store.search(question, limit: ArchiveQuestion.maximumEvidence).map(\.entry)
            let evidence = entries.map { ArchiveEvidence($0) }
            var text: String?
            var outcome = AIAnswerOutcome.declined
            var logged = "no matching records"
            if !evidence.isEmpty {
                do {
                    let raw = try await answerer.answer(question: question, evidence: evidence, targetLanguage: language)
                    text = ArchiveQuestion.sanitize(raw)
                    outcome = text == nil ? .declined : .shown
                    logged = text ?? raw
                } catch {
                    outcome = .failed
                    logged = AnalysisPipeline.describe(error)
                }
            }
            if logging {
                await store.recordAIAnswer(AIAnswerRecord(feature: .archiveQuestion, subject: question, answer: logged, outcome: outcome,
                                                          durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000)))
            }
            guard !Task.isCancelled, let self else { return }
            var cited: [VisualMemoryEntry] = []
            if let text {
                cited = ArchiveQuestion.citations(in: text, evidenceCount: entries.count).map { number in entries[number - 1] }
            }
            self.answer = ArchiveAnswer(question: question, text: text, isLoading: false, cited: cited)
        }
    }

    func dismissAnswer() {
        askTask?.cancel()
        answer = nil
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
