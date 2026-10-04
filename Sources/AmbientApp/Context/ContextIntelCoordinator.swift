import Foundation

/// Page-level intel, triggered when the front page changes (not by pixels):
/// - Movie / Anime mode: a work card once per work per day (Gemini).
/// - News mode: the background of a news story (Gemini with Google Search),
///   or, offline, earlier related reading from the archive.
actor ContextIntelCoordinator {
    struct Configuration: Sendable, Equatable {
        var mediaEnabled: Bool
        var newsEnabled: Bool
        var spoilerLevel: SpoilerLevel
        var targetLanguage: String
        var memoryEnabled: Bool
    }

    private let store: IntelStore
    private let research: (any MediaResearching)?
    private let media: MediaContext
    private let present: @Sendable (HUDMessage) async -> Void
    private var configuration: Configuration
    private var shown = CooldownCache(duration: 24 * 60 * 60)
    private var lastWorkKey: String?

    init(store: IntelStore, research: (any MediaResearching)?, media: MediaContext,
         configuration: Configuration, present: @escaping @Sendable (HUDMessage) async -> Void) {
        self.store = store
        self.research = research
        self.media = media
        self.configuration = configuration
        self.present = present
    }

    func update(_ configuration: Configuration) {
        self.configuration = configuration
    }

    func pageChanged(bundleIdentifier: String?, title: String?, url: URL?) async {
        let now = Date().timeIntervalSince1970
        if let reference = MediaTitleParser.parse(windowTitle: title, url: url, bundleIdentifier: bundleIdentifier) {
            if configuration.mediaEnabled, reference.workKey != lastWorkKey {
                lastWorkKey = reference.workKey
                await showWork(reference, now: now)
            }
            return
        }
        if lastWorkKey != nil, AppContextClassifier.classify(bundleIdentifier: bundleIdentifier, windowTitle: title) != .media {
            lastWorkKey = nil
            media.update(workTitle: nil, cast: [])
        }
        if configuration.newsEnabled, NewsDetector.isNewsArticle(url), let headline = NewsDetector.headline(from: title) {
            await showNews(headline: headline, url: url, now: now)
        }
    }

    // MARK: Media

    private func showWork(_ reference: MediaReference, now: TimeInterval) async {
        guard let research, research.isAvailable else { return }
        let cacheEntity = ExtractedEntity(type: .work, name: MediaPolicy.cacheName(for: reference, spoiler: configuration.spoilerLevel))
        var info: MediaInfoAnswer?
        if let cached = await store.knowledge(type: .work, canonical: cacheEntity.canonicalName) {
            guard cached.summary != TermExplanationSanitizer.declinedMarker else { return }
            info = cached.detail.flatMap { try? JSONDecoder().decode(MediaInfoAnswer.self, from: Data($0.utf8)) }
        } else {
            do {
                let answer = try await research.mediaInfo(for: reference, spoiler: configuration.spoilerLevel, targetLanguage: configuration.targetLanguage)
                let accepted = MediaPolicy.accept(answer)
                let json = accepted ? (try? JSONEncoder().encode(answer)).map { String(decoding: $0, as: UTF8.self) } : nil
                await store.saveKnowledge(entity: cacheEntity, summary: accepted ? answer.title : TermExplanationSanitizer.declinedMarker,
                                          detail: json, source: "gemini", ttl: 7 * 24 * 3600)
                info = accepted ? answer : nil
            } catch {
                Log.app.error("Work lookup failed: \(String(describing: error), privacy: .public)")
                return
            }
        }
        guard let info else { return }
        media.update(workTitle: info.title, cast: info.cast)
        guard shown.checkAndRecord("work:" + reference.workKey, now: now) else { return }

        let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"
        var lines: [String] = []
        if !info.originalWork.isEmpty { lines.append((japanese ? "原作 " : "Based on ") + info.originalWork) }
        let castLine = info.cast.prefix(3).map { "\($0.character)（\($0.performer)）" }.joined(separator: " / ")
        if !castLine.isEmpty { lines.append((japanese ? "出演 " : "Cast ") + castLine) }
        if let song = info.music.first { lines.append("♪ " + song) }
        if !info.synopsis.isEmpty { lines.append(info.synopsis) }
        var subtitle = [info.kind.uppercased(), info.year].filter { !$0.isEmpty }.joined(separator: " · ")
        if let episode = reference.episode { subtitle += japanese ? " · 第\(episode)話" : " · EP \(episode)" }
        let message = HUDMessage(
            kind: .mediaInfo,
            title: info.title,
            original: subtitle,
            detail: lines.joined(separator: "\n"),
            anchor: nil,
            features: PersonalizationFeatures(action: .identifyProduct, language: nil, bundleIdentifier: nil),
            targetLanguage: configuration.targetLanguage,
            confidence: info.confidence
        )
        await present(message)
    }

    // MARK: News

    private func showNews(headline: String, url: URL?, now: TimeInterval) async {
        guard shown.checkAndRecord("news:" + (url?.absoluteString ?? headline), now: now) else { return }
        let japanese = LanguageCode.base(configuration.targetLanguage) == "ja"

        if let research, research.isAvailable {
            do {
                let context = try await research.newsContext(headline: headline, targetLanguage: configuration.targetLanguage)
                guard context.isNewsStory, !context.background.isEmpty else { return }
                var lines = [context.background]
                lines += context.timeline.prefix(3).map { "\($0.date)  \($0.event)" }
                if !context.relatedPeople.isEmpty {
                    lines.append((japanese ? "関連人物 " : "People ") + "\(context.relatedPeople.count)" + (japanese ? "名: " : ": ")
                                 + context.relatedPeople.prefix(3).joined(separator: ", "))
                }
                await present(HUDMessage(kind: .newsContext, title: japanese ? "この出来事について" : "About this story",
                                         original: headline, detail: lines.joined(separator: "\n"), anchor: nil,
                                         targetLanguage: configuration.targetLanguage))
                return
            } catch {
                Log.app.error("News background failed: \(String(describing: error), privacy: .public)")
            }
        }

        // Offline: earlier related reading from the archive.
        guard configuration.memoryEnabled else { return }
        let related = await store.relatedPages(keywords: MediaPolicy.keywords(fromHeadline: headline), excludingURL: url,
                                               since: Date().addingTimeInterval(-30 * 24 * 3600))
        guard !related.isEmpty else { return }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: configuration.targetLanguage)
        let lines = related.map { "\(formatter.localizedString(for: $0.start, relativeTo: Date()))  \($0.title ?? "")" }
        await present(HUDMessage(kind: .newsContext, title: japanese ? "関連して読んだ記事" : "Related reading",
                                 original: headline, detail: lines.joined(separator: "\n"), anchor: nil,
                                 targetLanguage: configuration.targetLanguage))
    }
}
