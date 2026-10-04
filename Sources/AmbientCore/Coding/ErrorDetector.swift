import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// An error message found in a terminal / IDE / build log.
public struct DetectedError: Sendable, Equatable {
    /// Short label such as "TypeError", "error", "npm ERR!", "panic".
    public let kind: String
    /// The single most informative line.
    public let line: String
    /// A few surrounding lines for the model (truncated).
    public let context: String
    public let region: CGRect?
}

/// Finds real errors in on-screen logs and ignores normal output
/// ("0 errors", "Build succeeded", warnings, test passes).
public struct ErrorDetector: Sendable {
    public var contextLines = 6
    public var maximumContextLength = 600

    private struct Pattern {
        let kind: String
        let regex: String
    }

    /// Ordered from most to least specific.
    private static let patterns: [Pattern] = [
        Pattern(kind: "Traceback", regex: #"^Traceback \(most recent call last\)"#),
        Pattern(kind: "Exception", regex: #"^(?:[A-Za-z_][\w.]*\.)?[A-Z]\w*(?:Error|Exception|Fault)\b(?::|$)"#),
        Pattern(kind: "Uncaught", regex: #"^Uncaught\b"#),
        Pattern(kind: "Exception", regex: #"^Exception in thread\b"#),
        Pattern(kind: "panic", regex: #"^(?:panic|thread '.*' panicked)\b"#),
        Pattern(kind: "error", regex: #"^error(?:\[E\d+\])?:\s"#),
        Pattern(kind: "error", regex: #"^\S+?:\d+(?::\d+)?:\s*(?:fatal )?error:\s"#),
        Pattern(kind: "npm ERR!", regex: #"^npm ERR!"#),
        Pattern(kind: "fatal", regex: #"^fatal:\s"#),
        Pattern(kind: "Segmentation fault", regex: #"Segmentation fault"#),
        Pattern(kind: "command not found", regex: #":\s*command not found\b|^zsh: command not found"#),
        Pattern(kind: "No such file", regex: #"No such file or directory"#),
        Pattern(kind: "Permission denied", regex: #"Permission denied"#),
        Pattern(kind: "BUILD FAILED", regex: #"\b(?:BUILD FAILED|\*\* BUILD FAILED \*\*|Build failed)\b"#),
        Pattern(kind: "exit code", regex: #"(?:exited with|exit) (?:code|status) [1-9]\d*"#)
    ]

    /// Lines that look like errors but are normal output.
    private static let benign: [String] = [
        #"\b0 errors?\b"#, #"\bno errors?\b"#, #"error: 0\b"#, #"errors?: 0\b"#,
        #"\bwarning:"#, #"Build succeeded"#, #"BUILD SUCCEEDED"#, #"\bpassed\b"#, #"\bOK\b \("#
    ]

    public init() {}

    /// The most informative error across the regions, if any.
    public func detect(in regions: [RecognizedTextRegion]) -> DetectedError? {
        for region in regions {
            if let error = detect(in: region.text, region: region.boundingBox) {
                return error
            }
        }
        return nil
    }

    public func detect(in text: String, region: CGRect? = nil) -> DetectedError? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var match: (index: Int, kind: String)?
        for (index, line) in lines.enumerated() where !Self.isBenign(line) {
            guard let kind = Self.kind(of: line) else { continue }
            // A Python traceback ends with the actual exception line: prefer it.
            if kind == "Traceback" {
                if let last = lines[index...].lastIndex(where: { Self.kind(of: $0) == "Exception" && !Self.isBenign($0) }) {
                    match = (last, Self.exceptionName(lines[last]) ?? "Exception")
                } else {
                    match = (index, kind)
                }
                break
            }
            if match == nil {
                match = (index, kind == "Exception" ? (Self.exceptionName(line) ?? kind) : kind)
            }
        }
        guard let match else { return nil }

        let start = max(0, match.index - contextLines / 2)
        let end = min(lines.count, match.index + contextLines / 2 + 1)
        let context = String(lines[start..<end].joined(separator: "\n").prefix(maximumContextLength))
        return DetectedError(kind: match.kind, line: lines[match.index], context: context, region: region)
    }

    static func kind(of line: String) -> String? {
        patterns.first { line.range(of: $0.regex, options: .regularExpression) != nil }?.kind
    }

    static func isBenign(_ line: String) -> Bool {
        benign.contains { line.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// "TypeError: x is undefined" → "TypeError"; "java.lang.NullPointerException" → "NullPointerException".
    static func exceptionName(_ line: String) -> String? {
        guard let range = line.range(of: #"[A-Z]\w*(?:Error|Exception|Fault)\b"#, options: .regularExpression) else { return nil }
        return String(line[range])
    }
}
