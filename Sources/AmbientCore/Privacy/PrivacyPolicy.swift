import Foundation

/// Static privacy rules. The app layer feeds it the foreground app and window title.
public struct PrivacyPolicy: Sendable, Equatable {
    public static let defaultExcludedBundleIdentifiers: Set<String> = [
        // Password managers
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc", "com.apple.keychainaccess", "com.apple.Passwords",
        // Personal communication & media
        "com.apple.MobileSMS", "com.apple.Photos"
    ]

    public static let defaultSensitiveTitleKeywords: [String] = [
        "password", "passwort", "mot de passe", "パスワード", "暗証番号", "private browsing",
        "incognito", "シークレット", "プライベートブラウズ", "online banking", "ネットバンキング"
    ]

    public var excludedBundleIdentifiers: Set<String>
    public var sensitiveTitleKeywords: [String]

    public init(
        excludedBundleIdentifiers: Set<String> = PrivacyPolicy.defaultExcludedBundleIdentifiers,
        sensitiveTitleKeywords: [String] = PrivacyPolicy.defaultSensitiveTitleKeywords
    ) {
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
        self.sensitiveTitleKeywords = sensitiveTitleKeywords
    }

    public func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(bundleIdentifier)
    }

    public func allowsAnalysis(bundleIdentifier: String?, windowTitle: String?) -> Bool {
        if isExcluded(bundleIdentifier: bundleIdentifier) { return false }
        if let title = windowTitle?.lowercased(),
           sensitiveTitleKeywords.contains(where: { title.contains($0.lowercased()) }) {
            return false
        }
        return true
    }
}
