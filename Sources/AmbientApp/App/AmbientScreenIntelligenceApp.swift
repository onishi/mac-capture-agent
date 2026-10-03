import SwiftUI

@main
struct AmbientScreenIntelligenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app lives in the menu bar (see MenuBarController); this scene
        // only backs the standard Settings command (⌘,).
        Settings {
            SettingsView(settings: appDelegate.settings)
        }
    }
}
