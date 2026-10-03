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

    public static func classify(bundleIdentifier: String?) -> AppContextKind {
        guard let bundleIdentifier else { return .general }
        if codingBundleIdentifiers.contains(bundleIdentifier) { return .coding }
        if mediaBundleIdentifiers.contains(bundleIdentifier) { return .media }
        return .general
    }
}
