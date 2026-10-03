import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum BriefingError: Error {
    case unavailable
}

/// One-line context notes generated on-device by Apple Intelligence
/// (Foundation Models, macOS 26+). Only the already-recognized text is sent
/// to the local model; nothing leaves the Mac. Unavailable on older systems,
/// on unsupported hardware, or when Apple Intelligence is turned off.
final class AppleIntelligenceBriefingProvider: BriefingProvider, @unchecked Sendable {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func briefing(for request: BriefingRequest) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { throw BriefingError.unavailable }
            let session = LanguageModelSession(instructions: BriefingPrompt.instructions(targetLanguage: request.targetLanguage))
            let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 80)
            let response = try await session.respond(to: BriefingPrompt.prompt(for: request), options: options)
            return response.content
        }
        #endif
        throw BriefingError.unavailable
    }
}
