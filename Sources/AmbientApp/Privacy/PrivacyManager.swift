import Foundation

/// App-level privacy gate around `PrivacyPolicy`.
///
/// Guarantees of v0.1:
/// * frames live in memory only and are never written to disk,
/// * excluded apps are removed from the captured image by ScreenCaptureKit,
/// * analysis is skipped while an excluded app or a sensitive window is frontmost,
/// * no network access (the app has no network entitlement).
struct PrivacyManager: Sendable {
    let policy: PrivacyPolicy

    func allowsAnalysis(of snapshot: ForegroundContextProvider.Snapshot, windowTitle: String?) -> Bool {
        policy.allowsAnalysis(bundleIdentifier: snapshot.bundleIdentifier, windowTitle: windowTitle)
    }
}
