import Foundation

/// A frame of a stack trace.
public struct StackFrame: Sendable, Equatable {
    public let file: String
    public let line: Int
    public let function: String?

    /// "app.py:12 (load)".
    public var display: String {
        let name = (file as NSString).lastPathComponent
        return "\(name):\(line)" + (function.map { " (\($0))" } ?? "")
    }
}

/// Finds the frame in the user's own code, skipping libraries and the
/// runtime (SPEC LA-21). Rules only.
public enum StackTraceAnalyzer {
    private static let python = CompiledPattern(#"File "([^"]+)", line (\d+)(?:, in ([\w<>.]+))?"#)
    private static let javaScript = CompiledPattern(#"at (?:([\w$.<>\[\] ]+?) \()?((?:file://)?[^\s()]+?):(\d+):\d+\)?"#)
    private static let java = CompiledPattern(#"at ([\w$.]+)\(([\w$]+\.(?:java|kt|scala)):(\d+)\)"#)
    private static let generic = CompiledPattern(#"((?:/|\./)?[\w./\-]+\.(?:go|rs|swift|rb|c|cc|cpp|m|ts|tsx|js|jsx|py)):(\d+)"#)

    /// Paths that belong to libraries, package managers or the runtime.
    static let libraryMarkers = [
        "site-packages", "dist-packages", "node_modules", "/usr/lib", "/usr/local/lib", "/System/", "<frozen", "node:internal",
        "internal/", "java.base", "/rustc/", ".cargo/registry", "/go/src/runtime", "/go/pkg/mod", "/lib/python", ".rbenv", "gems/",
        "/Library/Developer", "/opt/homebrew", "webpack/bootstrap", "<anonymous>"
    ]

    public static func isLibrary(_ path: String) -> Bool {
        libraryMarkers.contains { path.contains($0) }
    }

    /// All frames found in `text`, in the order they appear.
    public static func frames(in text: String) -> [StackFrame] {
        var frames: [StackFrame] = []
        for line in text.split(separator: "\n").map(String.init) {
            if let groups = python.captures(in: line).first, groups.count > 2, let file = groups[1], let number = groups[2].flatMap({ Int($0) }) {
                frames.append(StackFrame(file: file, line: number, function: groups.count > 3 ? groups[3] : nil))
            } else if let groups = java.captures(in: line).first, groups.count > 3, let file = groups[2], let number = groups[3].flatMap({ Int($0) }) {
                let method = groups[1].map { String($0.split(separator: ".").suffix(2).joined(separator: ".")) }
                frames.append(StackFrame(file: (groups[1] ?? "") + "/" + file, line: number, function: method))
            } else if let groups = javaScript.captures(in: line).first, groups.count > 3, let file = groups[2], let number = groups[3].flatMap({ Int($0) }) {
                let function = groups[1]?.trimmingCharacters(in: .whitespaces)
                frames.append(StackFrame(file: file.replacingOccurrences(of: "file://", with: ""), line: number,
                                         function: function?.isEmpty == false ? function : nil))
            } else if let groups = generic.captures(in: line).first, groups.count > 2, let file = groups[1], let number = groups[2].flatMap({ Int($0) }) {
                frames.append(StackFrame(file: file, line: number, function: nil))
            }
        }
        return frames
    }

    /// The most relevant frame in the user's code: the deepest one for
    /// Python ("most recent call last"), otherwise the first one.
    public static func ownFrame(in text: String) -> StackFrame? {
        let own = frames(in: text).filter { !isLibrary($0.file) }
        return text.contains("most recent call last") ? own.last : own.first
    }
}
