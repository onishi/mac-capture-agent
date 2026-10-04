import Foundation

/// Cloud identification with Google Gemini (opt-in). Requests go through
/// `NetworkGate`; images are cropped regions, people are identified only from
/// names already written on screen (never from faces).
final class GeminiProvider: CloudIdentifying, @unchecked Sendable {
    private let gate: NetworkGate
    private let lock = NSLock()
    private var available = false
    private var model = GeminiAPI.defaultModel

    init(gate: NetworkGate) {
        self.gate = gate
    }

    /// Mirrors the network policy for synchronous checks in the pipeline.
    func configure(available: Bool, model: String) {
        lock.withLock {
            self.available = available
            self.model = model.isEmpty ? GeminiAPI.defaultModel : model
        }
    }

    var isAvailable: Bool {
        lock.withLock { available }
    }

    func identify(imageJPEG: Data, hint: VisualCategory, context: String, targetLanguage: String) async throws -> IdentificationAnswer {
        try await generate(
            IdentificationAnswer.self,
            system: IdentificationAnswer.instructions(targetLanguage: targetLanguage),
            parts: [.text("Expected subject: \(hint.rawValue). Nearby text: \(String(context.prefix(200)))"), .jpeg(imageJPEG)],
            schema: IdentificationAnswer.schema,
            purpose: "Identify \(hint.rawValue) (cropped image)",
            includesImage: true
        )
    }

    func publicFigure(named name: String, context: String, targetLanguage: String) async throws -> PublicFigureAnswer {
        try await generate(
            PublicFigureAnswer.self,
            system: PublicFigureAnswer.instructions(targetLanguage: targetLanguage),
            parts: [.text("Name on screen: \(name)\nContext: \(String(context.prefix(300)))")],
            schema: PublicFigureAnswer.schema,
            purpose: "Public figure lookup (name + context text)",
            includesImage: false
        )
    }

    private func generate<T: Decodable>(_ type: T.Type, system: String, parts: [GeminiAPI.Part], schema: [String: Any],
                                        purpose: String, includesImage: Bool) async throws -> T {
        let model = lock.withLock { self.model }
        guard let url = GeminiAPI.endpoint(model: model) else { throw GeminiAPI.APIError.invalidResponse }
        guard let key = KeychainStore.readAPIKey() else { throw NetworkGateError.denied(.noAPIKey) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try GeminiAPI.requestBody(system: system, parts: parts, schema: schema)
        let data = try await gate.send(request, purpose: purpose, includesImage: includesImage)
        return try GeminiAPI.decodeAnswer(T.self, from: data)
    }
}
