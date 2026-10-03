import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var newBundleIdentifier = ""

    var body: some View {
        Form {
            Section("Translation") {
                Picker("Translate into", selection: $settings.targetLanguage) {
                    ForEach(AppSettings.supportedTargetLanguages, id: \.self) { code in
                        Text(Self.languageName(code)).tag(code)
                    }
                }
                Toggle("I read English — don't translate it", isOn: $settings.englishIsFamiliar)
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

            Section("Privacy") {
                Text("Screen content is processed in memory on this Mac only. Nothing is saved to disk or sent over the network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
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
