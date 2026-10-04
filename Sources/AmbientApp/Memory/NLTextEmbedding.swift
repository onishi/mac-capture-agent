import Foundation
import NaturalLanguage

/// On-device sentence embeddings (NaturalLanguage). Embedding models are
/// loaded lazily per language and cached. Used only from the memory store actor.
final class NLTextEmbedding: TextEmbedding, @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: NLEmbedding] = [:]
    private var unavailable: Set<String> = []

    func vector(for text: String, language: String) -> [Float]? {
        let code = LanguageCode.base(language)
        guard let embedding = embedding(for: code), let vector = embedding.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    private func embedding(for code: String) -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[code] { return cached }
        guard !unavailable.contains(code) else { return nil }
        guard let embedding = NLEmbedding.sentenceEmbedding(for: NLLanguage(rawValue: code)) else {
            unavailable.insert(code)
            Log.vision.debug("No sentence embedding for \(code, privacy: .public); keyword search only")
            return nil
        }
        cache[code] = embedding
        return embedding
    }
}
