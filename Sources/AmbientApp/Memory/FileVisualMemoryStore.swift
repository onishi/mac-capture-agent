import Foundation

/// Visual memory persisted as a small JSON file in the app's (sandboxed)
/// Application Support folder, excluded from backups. Contains only the text
/// that was shown in the HUD — never images.
actor FileVisualMemoryStore: VisualMemoryStore {
    private var index: VisualMemoryIndex
    private var userLanguage: String
    private let fileURL: URL?
    private let embedding: any TextEmbedding
    private var saveTask: Task<Void, Never>?

    init(retentionDays: Int, userLanguage: String, embedding: any TextEmbedding = NLTextEmbedding()) {
        self.userLanguage = userLanguage
        self.embedding = embedding
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AmbientScreenIntelligence", isDirectory: true)
        fileURL = directory?.appendingPathComponent("visual-memory.json")

        var loaded = VisualMemoryIndex()
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(VisualMemoryIndex.self, from: data) {
            loaded = decoded
        }
        loaded.retention = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        loaded.prune(now: Date())
        index = loaded
    }

    func configure(retentionDays: Int, userLanguage: String) {
        index.retention = TimeInterval(max(1, retentionDays)) * 24 * 60 * 60
        self.userLanguage = userLanguage
        index.prune(now: Date())
        scheduleSave()
    }

    // MARK: VisualMemoryStore

    func remember(_ entry: VisualMemoryEntry) {
        var entry = entry
        if entry.embedding == nil {
            entry.embedding = embedding.vector(for: entry.translation, language: entry.targetLanguage ?? userLanguage)
        }
        index.add(entry, now: Date())
        Log.pipeline.debug("Remembered intel (\(self.index.entries.count) records)")
        scheduleSave()
    }

    func updateBriefing(_ briefing: String, for id: UUID) {
        index.updateBriefing(briefing, for: id)
        scheduleSave()
    }

    func search(_ query: String, limit: Int) -> [MemorySearchResult] {
        let now = Date()
        index.prune(now: now)
        let parsed = MemoryQueryParser.parse(query, now: now)
        let queryEmbedding = parsed.text.isEmpty ? nil : embedding.vector(for: parsed.text, language: userLanguage)
        return index.search(parsed, queryEmbedding: queryEmbedding, now: now, limit: limit)
    }

    func count() -> Int {
        index.entries.count
    }

    func removeAll() {
        index.removeAll()
        saveTask?.cancel()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        Log.privacy.info("Visual memory purged")
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.persist()
        }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(index)
            try data.write(to: fileURL, options: .atomic)
            var url = fileURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            Log.pipeline.error("Failed to save visual memory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
