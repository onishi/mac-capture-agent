import CoreServices
import Foundation

/// The Mac's built-in dictionaries via Dictionary Services (SPEC LA-5).
/// Works without Apple Intelligence; nothing leaves the Mac.
struct DictionaryLookup: DictionaryLooking {
    func definition(of term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(trimmed.count) else { return nil }
        let range = CFRange(location: 0, length: (trimmed as NSString).length)
        guard let raw = DCSCopyTextDefinition(nil, trimmed as CFString, range)?.takeRetainedValue() as String? else { return nil }
        return DictionaryDefinition.sanitize(raw, term: trimmed)
    }
}
