import Foundation

/// A visible window, as reported by the window server.
public struct WindowInfo: Sendable, Equatable {
    public let ownerName: String
    public let title: String

    public init(ownerName: String, title: String) {
        self.ownerName = ownerName
        self.title = title
    }
}

/// Guesses whether the screen is being shared, from the indicator windows
/// that meeting apps and browsers show while sharing. There is no public API
/// for this, so it is a heuristic: used for warnings only.
public enum ScreenShareHeuristics {
    private static let titlePatterns = [
        "is sharing your screen", "is sharing a window", "is sharing this tab", "is sharing your entire screen",
        "画面を共有しています", "ウィンドウを共有しています", "このタブを共有しています",
        "zoom share toolbar", "zoom share statusbar", "sharing control bar", "you are screen sharing",
        "stop share", "画面共有を停止"
    ]
    private static let ownerPatterns = ["cpthost"]   // Zoom's screen-share helper

    public static func isSharing(_ windows: [WindowInfo]) -> Bool {
        windows.contains { window in
            let title = window.title.lowercased()
            let owner = window.ownerName.lowercased()
            return titlePatterns.contains { title.contains($0) } || ownerPatterns.contains { owner.contains($0) }
        }
    }
}
