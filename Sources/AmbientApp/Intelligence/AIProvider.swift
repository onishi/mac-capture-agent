import CoreGraphics
import Foundation

/// Pluggable analysis backend. v0.1 ships only `LocalAIProvider` (rule-based
/// router); cloud providers (OpenAI, others) can conform later. Providers must
/// only ever receive cropped regions, never full-screen captures by default.
protocol AIProvider: Sendable {
    func analyze(image: CGImage, context: AnalysisContext) async throws -> AnalysisResult
}

/// Local, rule-based provider: wraps `AIRouter` and ignores the pixels.
struct LocalAIProvider: AIProvider {
    let router: AIRouter

    func analyze(image: CGImage, context: AnalysisContext) async throws -> AnalysisResult {
        AnalysisResult(actions: router.candidates(for: context))
    }
}
