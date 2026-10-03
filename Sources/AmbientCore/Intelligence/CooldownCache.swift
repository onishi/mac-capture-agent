import Foundation

/// Remembers what was shown recently so the same thing is not shown again
/// within `duration`. In-memory only.
public struct CooldownCache: Sendable {
    public let duration: TimeInterval
    public let maximumEntries: Int
    private var entries: [String: TimeInterval] = [:]

    public init(duration: TimeInterval = 5 * 60, maximumEntries: Int = 512) {
        self.duration = duration
        self.maximumEntries = max(1, maximumEntries)
    }

    public var count: Int { entries.count }

    public func isCoolingDown(_ key: String, now: TimeInterval) -> Bool {
        guard let last = entries[key] else { return false }
        return now - last < duration
    }

    public mutating func record(_ key: String, now: TimeInterval) {
        entries[key] = now
        if entries.count > maximumEntries { prune(now: now) }
    }

    /// Returns `true` (and records the key) when the key is not cooling down.
    public mutating func checkAndRecord(_ key: String, now: TimeInterval) -> Bool {
        guard !isCoolingDown(key, now: now) else { return false }
        record(key, now: now)
        return true
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func prune(now: TimeInterval) {
        entries = entries.filter { now - $0.value < duration }
        while entries.count > maximumEntries, let oldest = entries.min(by: { $0.value < $1.value }) {
            entries.removeValue(forKey: oldest.key)
        }
    }

    /// Cache key that ignores case, whitespace and surrounding punctuation, so
    /// that small OCR variations of the same sentence map to the same key.
    public static func key(action: SuggestedAction, payload: String?) -> String {
        let text = (payload ?? "")
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
        let collapsed = TextHeuristics.normalized(String(String.UnicodeScalarView(text)))
        return "\(action.rawValue):\(collapsed)"
    }
}
