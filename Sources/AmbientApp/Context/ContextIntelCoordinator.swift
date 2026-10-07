import Foundation

/// Page-level intel, triggered when the front page changes (not by pixels):
/// - Movie / Anime mode: a work card once per work per day (on-device model's
///   knowledge; well-known works only).
/// - News mode: general background of what the headline names (on-device
///   model) together with earlier related reading from the archive.
actor ContextIntelCoordinator {
    struct Configuration: Sendable, Equatable {
        var mediaEnabled: Bool
        var newsEnabled: Bool
        var spoilerLevel: SpoilerLevel
        var targetLanguage: String
        var memoryEnabled: Bool
        /// Record the on-device model's answers for the archive's AI LOG.
        var aiLogEnabled: Bool = false
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

    private func logAI(_ feature: IntelFeature, subject: String, answer: String, outcome: AIAnswerOutcome, since start: Date) async {
        guard configuration.aiLogEnabled else { return }
        await store.recordAIAnswer(AIAnswerRecord(feature: feature, subject: subject, answer: answer, outcome: outcome,
                                                  durationMilliseconds: Int(Date().timeIntervalSince(start) * 1000)))
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
            let start = Date()
            do {
                let answer = try await research.mediaInfo(for: reference, spoiler: configuration.spoilerLevel, targetLanguage: configuration.targetLanguage)
                let accepted = MediaPolicy.accept(answer)
                let logged = answer.isKnownWork
                    ? "\(answer.title) (\(answer.year)) — \(answer.cast.prefix(3).map { "\($0.character): \($0.performer)" }.joined(separator: ", "))"
                      + String(format: " (%.2f)", answer.confidence)
                    : "unknown work"
                await logAI(.mediaCard, subject: reference.title, answer: logged,
                            outcome: accepted ? .shown : (answer.isKnownWork ? .filtered : .declined), since: start)
                let json = accepted ? (try? JSONEncoder().encode(answer)).map { String(decoding: $0, as: UTF8.self) } : nil
                await store.saveKnowledge(entity: cacheEntity, summary: accepted ? answer.title : TermExplanationSanitizer.declinedMarker,
                                          detail: json, source: "on-device", ttl: 7 * 24 * 3600)
                info = accepted ? answer : nil
            } catch {
                Log.app.error("Work lookup failed: \(String(describing: error), privacy: .public)")
                await logAI(.mediaCard, subject: reference.title, answer: AnalysisPipeline.describe(error), outcome: .failed, since: start)
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
        var lines: [String] = []

        // General background from the on-device model (it cannot know the event itself).
        var hasBackground = false
        if let research, research.isAvailable {
            let start = Date()
            do {
                let context = try await research.newsContext(headline: headline, targetLanguage: configuration.targetLanguage)
                let usable = context.isNewsStory && !context.background.isEmpty
                await logAI(.newsBackground, subject: headline, answer: usable ? context.background : "nothing established to say",
                            outcome: usable ? .shown : .declined, since: start)
                if context.isNewsStory, !context.background.isEmpty {
                    hasBackground = true
                    lines.append(context.background)
                    if !context.relatedPeople.isEmpty {
                        lines.append((japanese ? "関連人物 " : "People ") + context.relatedPeople.prefix(3).joined(separator: ", "))
                    }
                }
            } catch {
                Log.app.error("News background failed: \(String(describing: error), privacy: .public)")
                await logAI(.newsBackground, subject: headline, answer: AnalysisPipeline.describe(error), outcome: .failed, since: start)
            }
        }

        // The timeline comes from the user's own reading history.
        if configuration.memoryEnabled {
            let related = await store.relatedPages(keywords: MediaPolicy.keywords(fromHeadline: headline), excludingURL: url,
                                                   since: Date().addingTimeInterval(-30 * 24 * 3600))
            if !related.isEmpty {
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = Locale(identifier: configuration.targetLanguage)
                if hasBackground { lines.append(japanese ? "以前に読んだ関連記事:" : "Read earlier:") }
                lines += related.map { "\(formatter.localizedString(for: $0.start, relativeTo: Date()))  \($0.title ?? "")" }
            }
        }
        guard !lines.isEmpty else { return }
        let title: String
        if hasBackground {
            title = japanese ? "この話題の背景（端末内の推定）" : "Background (on-device estimate)"
        } else {
            title = japanese ? "関連して読んだ記事" : "Related reading"
        }
        await present(HUDMessage(kind: .newsContext, title: title, original: headline, detail: lines.joined(separator: "\n"),
                                 anchor: nil, targetLanguage: configuration.targetLanguage))
    }
}
