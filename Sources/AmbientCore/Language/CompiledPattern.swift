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
}
