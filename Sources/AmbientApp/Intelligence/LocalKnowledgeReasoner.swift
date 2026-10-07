import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Identification and media / news knowledge from the on-device model's own
/// knowledge (LOCAL_AI.md LA-1〜LA-4). Replaces the former cloud provider:
/// nothing leaves the Mac. The model reads text only (classification labels,
/// names and titles), so every answer is treated as an estimate.
extension AppleIntelligenceReasoner: VisualIdentifying, MediaResearching {
    func identify(labels: [VisualLabel], hint: VisualCategory, context: String, targetLanguage: String) async throws -> IdentificationAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable, !labels.isEmpty else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: IdentificationAnswer.instructions(targetLanguage: targetLanguage))
            let response = try await session.respond(
                to: IdentificationAnswer.prompt(labels: labels, hint: hint, context: context),
                generating: IdentificationOutput.self,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 200)
            )
            let output = response.content
            return IdentificationAnswer(
                category: output.category,
                name: output.name,
                scientificName: output.scientificName,
                facts: Array(output.facts.prefix(3)),
                confidence: output.confidence
            )
        }
        #endif
        throw BriefingError.unavailable
    }

    func publicFigure(named name: String, context: String, targetLanguage: String) async throws -> PublicFigureAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: PublicFigureAnswer.instructions(targetLanguage: targetLanguage))
            let response = try await session.respond(
                to: "Name on screen: \(name)\nContext: \(String(context.prefix(300)))",
                generating: PublicFigureOutput.self,
                options: GenerationOptions(temperature: 0, maximumResponseTokens: 160)
            )
            let output = response.content
            return PublicFigureAnswer(
                isPublicFigure: output.isPublicFigure,
                name: output.name,
                role: output.role,
                knownFor: Array(output.knownFor.prefix(3)),
                confidence: output.confidence
            )
        }
        #endif
        throw BriefingError.unavailable
    }

    func mediaInfo(for reference: MediaReference, spoiler: SpoilerLevel, targetLanguage: String) async throws -> MediaInfoAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: MediaInfoAnswer.instructions(
                spoiler: spoiler, episode: reference.episode, targetLanguage: targetLanguage))
            var prompt = "Window title: \(reference.title)\nSite: \(reference.site.rawValue)"
            if let season = reference.season { prompt += "\nSeason: \(season)" }
            if let episode = reference.episode { prompt += "\nEpisode: \(episode)" }
            let response = try await session.respond(
                to: prompt,
                generating: MediaInfoOutput.self,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 360)
            )
            let output = response.content
            return MediaInfoAnswer(
                isKnownWork: output.isKnownWork,
                title: output.title,
                kind: output.kind,
                year: output.year,
                originalWork: output.originalWork,
                cast: output.cast.prefix(6).map { CastMember(character: $0.character, performer: $0.performer) },
                music: Array(output.music.prefix(2)),
                synopsis: output.synopsis,
                confidence: output.confidence
            )
        }
        #endif
        throw BriefingError.unavailable
    }

    func newsContext(headline: String, targetLanguage: String) async throws -> NewsContextAnswer {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: NewsContextAnswer.instructions(targetLanguage: targetLanguage))
            let response = try await session.respond(
                to: "Headline: \(String(headline.prefix(200)))",
                generating: NewsBackgroundOutput.self,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 200)
            )
            let output = response.content
            return NewsContextAnswer(
                isNewsStory: output.isNewsStory,
                background: output.background,
                timeline: [],
                relatedPeople: Array(output.relatedPeople.prefix(5))
            )
        }
        #endif
        throw BriefingError.unavailable
    }
}

// MARK: - Circle to look up (LA-60)

extension AppleIntelligenceReasoner: RegionDescribing {
    func describe(text: String, appName: String?, targetLanguage: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: RegionDescription.instructions(targetLanguage: targetLanguage))
            let response = try await session.respond(
                to: "App: \(appName ?? "unknown")\nCircled text:\n\(String(text.prefix(RegionDescription.maximumInputLength)))",
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 120)
            )
            return response.content
        }
        #endif
        throw BriefingError.unavailable
    }
}

// MARK: - Ask the archive (LA-30)

extension AppleIntelligenceReasoner: ArchiveAnswering {
    func answer(question: String, evidence: [ArchiveEvidence], targetLanguage: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: ArchiveQuestion.instructions(targetLanguage: targetLanguage))
            let response = try await session.respond(
                to: ArchiveQuestion.prompt(question: question, evidence: evidence),
                options: GenerationOptions(temperature: 0, maximumResponseTokens: 220)
            )
            return response.content
        }
        #endif
        throw BriefingError.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct IdentificationOutput {
    @Guide(description: "One of: animal, plant, landmark, food, product, none.")
    var category: String
    @Guide(description: "Common name in the requested language, as specific as the evidence allows. Empty if none.")
    var name: String
    @Guide(description: "Scientific name (animals, plants), city/country (landmarks), cuisine (food) or brand (products). May be empty.")
    var scientificName: String
    @Guide(description: "Up to 3 short facts you are sure of.")
    var facts: [String]
    @Guide(description: "Probability from 0 to 1 that the name is correct given only the labels and the text.")
    var confidence: Double
}

@available(macOS 26.0, *)
@Generable
struct PublicFigureOutput {
    @Guide(description: "True only for a widely known public figure you are sure about.")
    var isPublicFigure: Bool
    @Guide(description: "Full name as commonly written. Empty if not a public figure.")
    var name: String
    @Guide(description: "One short phrase such as actor or prime minister. Empty if not a public figure.")
    var role: String
    @Guide(description: "Up to 3 works or achievements.")
    var knownFor: [String]
    @Guide(description: "Probability from 0 to 1 that this is the right person.")
    var confidence: Double
}

@available(macOS 26.0, *)
@Generable
struct CastOutput {
    @Guide(description: "Character name.")
    var character: String
    @Guide(description: "Actor or voice actor.")
    var performer: String
}

@available(macOS 26.0, *)
@Generable
struct MediaInfoOutput {
    @Guide(description: "True only for a published film, series or anime you know well.")
    var isKnownWork: Bool
    @Guide(description: "Official title in the requested language.")
    var title: String
    @Guide(description: "One of: movie, anime, series, video.")
    var kind: String
    @Guide(description: "Release year, or empty.")
    var year: String
    @Guide(description: "Original work (manga, novel) it is based on, or empty.")
    var originalWork: String
    @Guide(description: "Up to 6 main characters with their actor or voice actor.")
    var cast: [CastOutput]
    @Guide(description: "Up to 2 theme songs, or empty.")
    var music: [String]
    @Guide(description: "At most 2 sentences, following the spoiler rule.")
    var synopsis: String
    @Guide(description: "Probability from 0 to 1 that this is the right work.")
    var confidence: Double
}

@available(macOS 26.0, *)
@Generable
struct NewsBackgroundOutput {
    @Guide(description: "False if nothing long-established can be said or it is not news.")
    var isNewsStory: Bool
    @Guide(description: "One or two sentences of general background, never about the recent event itself.")
    var background: String
    @Guide(description: "Up to 5 well-known people named in or clearly tied to the headline.")
    var relatedPeople: [String]
}
#endif
