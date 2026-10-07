import Foundation
import Security

/// v0.8–v0.10 could keep a Gemini API key in the Keychain. The app is local
/// only now (ROADMAP D-7), so a leftover key is deleted at launch.
enum LegacyCloudCleanup {
    private static let service = "com.onishi.AmbientScreenIntelligence.gemini"
    private static let account = "api-key"
    private static let obsoleteDefaults = ["cloudEnabled", "geminiModel"]

    static func removeStoredAPIKey(defaults: UserDefaults = .standard) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            Log.privacy.info("Removed the legacy cloud API key")
        }
        obsoleteDefaults.forEach(defaults.removeObject(forKey:))
    }
}
