import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onResetPersonalization: (() -> Void)?
    var onPurgeMemory: (() -> Void)?
    var briefingAvailable: Bool = AppleIntelligenceBriefingProvider().isAvailable
    @State private var newBundleIdentifier = ""
    @State private var apiKeyDraft = ""

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
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                Toggle("Classify images (experimental)", isOn: $settings.imageClassificationEnabled)
                Toggle("Follow the display under the mouse pointer", isOn: $settings.followMouseDisplay)
            }

            Section("Intelligence") {
                Toggle("Briefing notes (Apple Intelligence, on-device)", isOn: $settings.briefingEnabled)
                    .disabled(!briefingAvailable)
                Toggle("Explain technical terms and judge borderline text", isOn: $settings.reasoningEnabled)
                    .disabled(!briefingAvailable)
                (briefingAvailable
                    ? Text("Adds a one-line note about what the text means for you. Runs entirely on this Mac.")
                    : Text("Requires macOS 26 with Apple Intelligence turned on."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visual memory") {
                Toggle("Archive intel shown in the HUD", isOn: $settings.memoryEnabled)
                Toggle("Remember pages you read (titles, URLs, reading time)", isOn: $settings.pageTrackingEnabled)
                    .disabled(!settings.memoryEnabled)
                Toggle("Read the URL of the front browser tab", isOn: $settings.readBrowserURLs)
                    .disabled(!settings.memoryEnabled || !settings.pageTrackingEnabled)
                Toggle("Offer to pick up where you left off", isOn: $settings.resumeEnabled)
                    .disabled(!settings.memoryEnabled || !settings.pageTrackingEnabled)
                Picker("Keep for", selection: $settings.memoryRetentionDays) {
                    ForEach(AppSettings.retentionChoices, id: \.self) { days in
                        (days == 1 ? Text("1 day") : Text("\(days) days")).tag(days)
                    }
                }
                .disabled(!settings.memoryEnabled)
                Text("Archived: text shown in the HUD, and — if enabled — titles, URLs (without query strings) and reading time of pages, for automatic bookmarks and work sessions. Never screenshots. On this Mac only; excluded apps are never recorded. Search with ⌥⌘K. macOS asks once per browser before URLs can be read.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let onPurgeMemory {
                    Button("Purge Archive", role: .destructive, action: onPurgeMemory)
                }
            }

            Section("HUD") {
                Picker("Position", selection: $settings.hudPosition) {
                    ForEach(HUDPosition.allCases) { position in
                        Text(LocalizedStringKey(position.displayName)).tag(position)
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
                Toggle("Pretend the screen is being shared", isOn: $settings.pretendScreenSharing)
                Text("Draws changed regions, OCR areas, router scores, counters and timings on screen. Never shows recognized text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cloud identification (Gemini)") {
                Toggle("Use Google Gemini to identify animals, plants, landmarks and public figures", isOn: $settings.cloudEnabled)
                HStack {
                    SecureField(settings.hasGeminiKey ? LocalizedStringKey("API key saved in Keychain") : LocalizedStringKey("Gemini API key"), text: $apiKeyDraft)
                    Button(settings.hasGeminiKey ? LocalizedStringKey("Replace") : LocalizedStringKey("Save")) {
                        settings.saveGeminiKey(apiKeyDraft)
                        apiKeyDraft = ""
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if settings.hasGeminiKey {
                        Button("Remove", role: .destructive) { settings.removeGeminiKey() }
                    }
                }
                TextField("Model", text: $settings.geminiModel)
                Toggle("Identify public figures named on screen", isOn: $settings.publicFigureEnabled)
                    .disabled(!settings.cloudEnabled)
                Text("Nothing is sent until this is on and a key is saved, and never in Battery mode. Only a cropped image region (animals, plants, landmarks) or a name with nearby text (public figures) is sent — never the whole screen, never faces, never text containing secrets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !settings.sentRecords.isEmpty {
                    ForEach(settings.sentRecords) { record in
                        HStack {
                            Text(record.date, style: .time).font(.caption.monospaced())
                            Text(record.purpose).font(.caption)
                            Spacer()
                            Text(verbatim: "\(record.bytes / 1024) KB\(record.includesImage ? " · image" : "")")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Movie, anime & news") {
                Toggle("Movie / Anime mode (work card, cast on screen)", isOn: $settings.mediaModeEnabled)
                Picker("Spoilers", selection: $settings.spoilerLevel) {
                    ForEach(SpoilerLevel.allCases) { level in
                        Text(LocalizedStringKey(level.displayName)).tag(level)
                    }
                }
                .disabled(!settings.mediaModeEnabled)
                Toggle("News mode (background of the story)", isOn: $settings.newsModeEnabled)
                Text("Work cards and news backgrounds use Gemini (window title or headline only). Without it, News mode shows related pages you read earlier. Both need “Remember pages you read”. “Up to where I am” uses the episode number in the title; without one it behaves like “No spoilers”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screen sharing") {
                Toggle("Warn about secrets while sharing the screen", isOn: $settings.warnSensitiveWhileSharing)
                Toggle("Cover secrets while sharing (experimental)", isOn: $settings.redactWhileSharing)
                Text("API keys, private keys, tokens, card numbers and passwords are detected on-device. Their values are never stored or shown. Text containing them is never translated or archived.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Screen content is processed in memory on this Mac. Screen images are never saved. Nothing is sent over the network unless you turn on Cloud identification.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 820)
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
