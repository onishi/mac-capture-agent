import AppKit

/// Reads the front tab's URL from browsers via Apple Events (the user grants
/// access per browser the first time). Firefox has no AppleScript support.
/// Must run on the main thread (NSAppleScript is not thread-safe).
@MainActor
final class BrowserURLProvider {
    private static let scripts: [String: String] = [
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to get URL of current tab of front window",
        "com.apple.SafariTechnologyPreview": "tell application id \"com.apple.SafariTechnologyPreview\" to get URL of current tab of front window",
        "com.google.Chrome": chromium("com.google.Chrome"),
        "com.microsoft.edgemac": chromium("com.microsoft.edgemac"),
        "com.brave.Browser": chromium("com.brave.Browser"),
        "company.thebrowser.Browser": chromium("company.thebrowser.Browser"),
        "com.vivaldi.Vivaldi": chromium("com.vivaldi.Vivaldi")
    ]

    private static func chromium(_ bundleID: String) -> String {
        "tell application id \"\(bundleID)\" to get URL of active tab of front window"
    }

    private var compiled: [String: NSAppleScript] = [:]
    /// Browsers that refused (user denied automation); not asked again this run.
    private var denied: Set<String> = []

    static func supports(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { scripts[$0] != nil } ?? false
    }

    /// The sanitized URL of the front tab, or nil (unsupported, denied, no window).
    func currentURL(for bundleIdentifier: String?) -> URL? {
        guard let bundleIdentifier, let source = Self.scripts[bundleIdentifier], !denied.contains(bundleIdentifier) else { return nil }
        let script = compiled[bundleIdentifier] ?? NSAppleScript(source: source)
        guard let script else { return nil }
        compiled[bundleIdentifier] = script
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 {   // errAEEventNotPermitted
                denied.insert(bundleIdentifier)
                Log.privacy.info("Automation not permitted for a browser; URLs will not be read")
            }
            return nil
        }
        return result.stringValue.flatMap(URLSanitizer.sanitize)
    }
}
