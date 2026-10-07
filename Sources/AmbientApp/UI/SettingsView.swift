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
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }
                Toggle("Classify images (experimental)", isOn: $settings.imageClassificationEnabled)
                Toggle("Follow the display under the mouse pointer", isOn: $settings.followMouseDisplay)
            }

            Section("Features & priority") {
                Text("Turn each kind of intel on or off. When several could be shown at the same moment, the one higher in this list wins (also when you circle something).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(settings.features.order.enumerated()), id: \.element) { index, feature in
                    featureRow(feature, rank: index, count: settings.features.order.count)
                }
                Button("Reset Order") { settings.resetFeatureOrder() }
            }

            Section("Other features") {
                ForEach(IntelFeature.allCases.filter { !$0.isRankable }) { feature in
                    featureRow(feature, rank: nil, count: 0)
                }
                (briefingAvailable
                    ? Text("Items marked “AI” use Apple Intelligence on this Mac.")
                    : Text("Items marked “AI” need macOS 26 with Apple Intelligence turned on; without it they do nothing."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Visual memory") {
                Toggle("Archive intel shown in the HUD", isOn: $settings.memoryEnabled)
                Toggle("Remember pages you read (titles, URLs, reading time)", isOn: $settings.pageTrackingEnabled)
                    .disabled(!settings.memoryEnabled)
                Toggle("Keep AI answers to review in the archive (AI LOG)", isOn: $settings.aiLogEnabled)
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

            Section("On-device knowledge") {
                Text("Everything runs on this Mac; the app never sends anything over the network. The on-device model cannot see images — it guesses from image labels and nearby text, so names are marked “possibly” unless the screen shows them. Abbreviations defined on screen and common errors are explained even without Apple Intelligence. Circling with ⌥ held always answers: a QR code, an error, a translation, units, a term, code, a picture or — with Apple Intelligence — what the text is about.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Movie, anime & news") {
                Picker("Spoilers", selection: $settings.spoilerLevel) {
                    ForEach(SpoilerLevel.allCases) { level in
                        Text(LocalizedStringKey(level.displayName)).tag(level)
                    }
                }
                .disabled(!settings.isEnabled(.mediaCard))
                Text("Work cards and news backgrounds come from the on-device model’s own knowledge (well-known works only; it does not know recent news). News mode also lists related pages you read earlier. Both need “Remember pages you read”. “Up to where I am” uses the episode number in the title; without one it behaves like “No spoilers”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screen sharing") {
                Toggle("Cover secrets while sharing (experimental)", isOn: $settings.redactWhileSharing)
                Text("API keys, private keys, tokens, card numbers and passwords are detected on-device. Their values are never stored or shown. Text containing them is never translated or archived.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Screen content is processed in memory on this Mac. Screen images are never saved. Nothing is ever sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 860)
    }

    /// One feature: switch, "AI" mark, and ▲▼ for the rankable ones.
    private func featureRow(_ feature: IntelFeature, rank: Int?, count: Int) -> some View {
        HStack(spacing: 8) {
            if let rank {
                Text(verbatim: "\(rank + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
            }
            Toggle(isOn: Binding(get: { settings.isEnabled(feature) }, set: { settings.setEnabled(feature, $0) })) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(feature.title))
                    if feature.requiresLanguageModel {
                        Text(verbatim: "AI")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5)))
                    }
                }
            }
            if let rank {
                Button {
                    settings.move(feature, up: true)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(rank == 0)
                .accessibilityLabel(Text("Move Up"))
                Button {
                    settings.move(feature, up: false)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(rank >= count - 1)
                .accessibilityLabel(Text("Move Down"))
            }
        }
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
