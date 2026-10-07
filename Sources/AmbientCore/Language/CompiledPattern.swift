import Foundation

/// A regular expression compiled once. `String.range(of:options: .regularExpression)`
/// recompiles the pattern on every call, which dominated the per-frame cost of
/// the detectors that run on every OCR line (PerformanceBudgetTests).
public struct CompiledPattern: @unchecked Sendable {
    // NSRegularExpression is immutable and documented as thread-safe.
    private let regex: NSRegularExpression?

    public init(_ pattern: String, caseInsensitive: Bool = false) {
        regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// The first match in `text` (optionally within `range`), or nil.
    /// An invalid pattern never matches.
    public func firstRange(in text: String, range: Range<String.Index>? = nil) -> Range<String.Index>? {
        guard let regex else { return nil }
        let searchRange = NSRange(range ?? text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: searchRange) else { return nil }
        return Range(match.range, in: text)
    }

    public func matches(_ text: String) -> Bool {
        firstRange(in: text) != nil
    }

    /// Every match with its range in `text` and its capture groups (index 0 is the whole match).
    public func matchesWithRanges(in text: String) -> [(range: Range<String.Index>, groups: [String?])] {
        guard let regex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match -> (range: Range<String.Index>, groups: [String?])? in
            guard let whole = Range(match.range, in: text) else { return nil }
            let groups: [String?] = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            return (range: whole, groups: groups)
        }
    }

    /// Every match's capture groups (index 0 is the whole match; nil when a group did not take part).
    public func captures(in text: String) -> [[String?]] {
        guard let regex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
        }
    }
}
