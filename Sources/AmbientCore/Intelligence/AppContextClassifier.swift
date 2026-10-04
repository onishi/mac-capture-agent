import Foundation

/// The kind of activity the foreground app suggests. Future modes (Coding Mode,
/// Movie Mode) hook in here.
public enum AppContextKind: String, Sendable, Equatable {
    case general
    case coding
    case media
}

public enum AppContextClassifier {
    public static let codingBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.sublimetext.4", "dev.warp.Warp-Stable",
        "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.mitchellh.ghostty"
    ]
    public static let mediaBundleIdentifiers: Set<String> = [
        "com.apple.TV", "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.netflix.Netflix", "io.iina"
    ]

    public static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"
    ]

    /// Window titles of developer sites that switch a browser into Coding Mode.
    static let codingTitleKeywords = ["github", "gitlab", "bitbucket", "stack overflow", "pull request"]

    /// Window titles of streaming sites that switch a browser into media mode.
    static let mediaTitleKeywords = ["youtube", "netflix", "prime video", "disney+", "crunchyroll", "hulu", "u-next", "abema", "dアニメストア"]

    public static func classify(bundleIdentifier: String?, windowTitle: String? = nil) -> AppContextKind {
        guard let bundleIdentifier else { return .general }
        if codingBundleIdentifiers.contains(bundleIdentifier) { return .coding }
        if mediaBundleIdentifiers.contains(bundleIdentifier) { return .media }
        if browserBundleIdentifiers.contains(bundleIdentifier), let title = windowTitle?.lowercased(),
           codingTitleKeywords.contains(where: { title.contains($0) }) {
            return .coding
        }
        if browserBundleIdentifiers.contains(bundleIdentifier), let title = windowTitle?.lowercased(),
           mediaTitleKeywords.contains(where: { title.contains($0) }) {
            return .media
        }
        return .general
    }

    public static func classify(_ context: AnalysisContext) -> AppContextKind {
        classify(bundleIdentifier: context.bundleIdentifier, windowTitle: context.windowTitle)
    }
}
