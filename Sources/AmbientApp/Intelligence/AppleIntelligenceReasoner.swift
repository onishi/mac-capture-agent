import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Term explanations and second-stage routing with Apple's on-device
/// Foundation Models (macOS 26+, Apple Intelligence). Only recognized text is
/// passed to the local model; nothing leaves the Mac.
final class AppleIntelligenceReasoner: TermExplaining, RouterJudging, @unchecked Sendable {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func explain(term: String, context: String, targetLanguage: String) async throws -> TermExplanation {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: """
                You decide whether a term seen on screen deserves a short explanation, and write it. \
                Explain only specialized jargon (technical, scientific, legal, financial, domain acronyms) \
                that a general reader would likely not know. Do NOT explain everyday words, brand or product \
                names, people, places, or terms the context already defines. Prefer not explaining. \
                Write the explanation in the language with code "\(targetLanguage)", one or two short sentences.
                """)
            let prompt = """
                Term: \(term)
                Context: \(String(context.prefix(BriefingPrompt.maximumInputLength)))
                """
            let response = try await session.respond(
                to: prompt,
                generating: TermExplanationOutput.self,
                options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 160)
            )
            let output = response.content
            return TermExplanation(
                shouldExplain: output.shouldExplain,
                expansion: output.expansion.isEmpty ? nil : output.expansion,
                summary: output.explanation
            )
        }
        #endif
        throw BriefingError.unavailable
    }

    func shouldShow(_ candidate: RoutedAction, appName: String?, targetLanguage: String) async throws -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable, let payload = candidate.payload else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: """
                You are an ambient screen intelligence router. Your task is NOT to describe everything visible. \
                Decide whether the candidate below would be genuinely useful to show the user right now. \
                Prefer ignore. Avoid obvious information, UI labels, navigation, ads, and boilerplate. \
                The user reads the language with code "\(targetLanguage)".
                """)
            let prompt = """
                Action: \(candidate.action.rawValue)
                Text: \(String(payload.prefix(BriefingPrompt.maximumInputLength)))
                App: \(appName ?? "unknown")
                """
            let response = try await session.respond(
                to: prompt,
                generating: RouterVerdictOutput.self,
                options: GenerationOptions(temperature: 0, maximumResponseTokens: 40)
            )
            return response.content.show
        }
        #endif
        throw BriefingError.unavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct TermExplanationOutput {
    @Guide(description: "True only if the term is specialized jargon a general reader would likely not know and the context does not already explain it.")
    var shouldExplain: Bool
    @Guide(description: "The expanded form if the term is an abbreviation (e.g. Retrieval-Augmented Generation), otherwise an empty string.")
    var expansion: String
    @Guide(description: "One or two short sentences explaining the term in the requested language. Empty if shouldExplain is false.")
    var explanation: String
}

@available(macOS 26.0, *)
@Generable
struct RouterVerdictOutput {
    @Guide(description: "True only if showing this to the user now would provide meaningful value.")
    var show: Bool
}
#endif
