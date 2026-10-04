import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onResetPersonalization: (() -> Void)?
    var onPurgeMemory: (() -> Void)?
    var briefingAvailable: Bool = AppleIntelligenceBriefingProvider().isAvailable
    @State private var newBundleIdentifier = ""

    init(settings: AppSettings, onResetPersonalization: (() -> Void)? = nil, onPurgeMemory: (() -> Void)? = nil) {
        _settings = ObservedObject(wrappedValue: settings)
        self.onResetPersonalization = onResetPersonalization
        self.onPurgeMemory = onPurgeMemory
    }

    var body: some View {
        Form {
            Section("Translation") {
                Picker("Translate into", selection: $settings.targetLanguage) {
                    ForEach(AppSettings.supportedTargetLanguages, id: \.self) { code in
                        Text(Self.languageName(code)).tag(code)
                    }
                }
                Toggle("I read English — don't translate it", isOn: $settings.englishIsFamiliar)
                if !settings.skippedLanguages.isEmpty {
                    ForEach(settings.skippedLanguages.sorted(), id: \.self) { code in
                        HStack {
                            Text("Not translated: \(Self.languageName(code))")
                            Spacer()
                            Button {
                                settings.skippedLanguages.remove(code)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Text("Translation runs on-device. Install language models in System Settings › General › Language & Region › Translation Languages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Analysis") {
                Picker("Mode", selection: $settings.performanceMode) {
                    ForEach(PerformanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Classify images (experimental)", isOn: $settings.imageClassificationEnabled)
                Toggle("Follow the display under the mouse pointer", isOn: $settings.followMouseDisplay)
            }

            Section("Intelligence") {
                Toggle("Briefing notes (Apple Intelligence, on-device)", isOn: $settings.briefingEnabled)
                    .disabled(!briefingAvailable)
                Text(briefingAvailable
                     ? "Adds a one-line note about what the text means for you. Runs entirely on this Mac."
                     : "Requires macOS 26 with Apple Intelligence turned on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visual memory") {
                Toggle("Archive intel shown in the HUD", isOn: $settings.memoryEnabled)
                Picker("Keep for", selection: $settings.memoryRetentionDays) {
                    ForEach(AppSettings.retentionChoices, id: \.self) { days in
                        Text(days == 1 ? "1 day" : "\(days) days").tag(days)
                    }
                }
                .disabled(!settings.memoryEnabled)
                Text("Only the text shown in the HUD is archived (never screenshots), on this Mac only. Search it with ⌥⌘K.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let onPurgeMemory {
                    Button("Purge Archive", role: .destructive, action: onPurgeMemory)
                }
            }

            Section("HUD") {
                Picker("Position", selection: $settings.hudPosition) {
                    ForEach(HUDPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                Text("Hovering the HUD keeps it on screen and tells the app the information was useful. Use “Not Useful” in the menu bar to see less of something.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let onResetPersonalization {
                    Button("Reset Learned Preferences", action: onResetPersonalization)
                }
            }

            Section("Excluded apps") {
                ForEach(settings.excludedBundleIdentifiers.sorted(), id: \.self) { identifier in
                    HStack {
                        Text(identifier).font(.callout.monospaced())
                        Spacer()
                        Button {
                            settings.excludedBundleIdentifiers.remove(identifier)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("Bundle identifier (e.g. com.example.app)", text: $newBundleIdentifier)
                        .onSubmit(addBundleIdentifier)
                    Button("Add", action: addBundleIdentifier)
                        .disabled(newBundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("Excluded apps are removed from the captured image and never analyzed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle("Debug overlay", isOn: $settings.debugOverlay)
                Text("Draws changed regions, OCR areas, router scores, counters and timings on screen. Never shows recognized text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Screen content is processed in memory on this Mac only. Nothing is saved to disk or sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 720)
    }

    private func addBundleIdentifier() {
        let identifier = newBundleIdentifier.trimmingCharacters(in: .whitespaces)
        guard !identifier.isEmpty else { return }
        settings.excludedBundleIdentifiers.insert(identifier)
        newBundleIdentifier = ""
    }

    private static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
