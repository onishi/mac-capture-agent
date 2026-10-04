import AppKit
import Combine

@MainActor
final class ArchiveViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [MemorySearchResult] = []
    @Published private(set) var totalRecords = 0
    @Published private(set) var copiedID: UUID?
    @Published private(set) var isSearching = false

    let retentionDays: () -> Int
    let memoryEnabled: () -> Bool
    private let store: any VisualMemoryStore
    private let onOpen: (VisualMemoryEntry) -> Void
    private var queryObservation: AnyCancellable?
    private var searchTask: Task<Void, Never>?

    init(
        store: any VisualMemoryStore,
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
            .sink { [weak self] _ in self?.refresh() }
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

    func purge() {
        let store = self.store
        Task { [weak self] in
            await store.removeAll()
            self?.refresh()
        }
    }
}
