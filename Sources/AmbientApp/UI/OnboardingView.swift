import AppKit
import SwiftUI

/// First-run guide: what the app does, the permissions it needs, optional
/// features and the privacy promise. Re-openable from the menu.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .briefing
    @Published private(set) var state: OnboardingState

    let settings: AppSettings
    private let appleIntelligenceAvailable: Bool
    private let onFinish: () -> Void
    private let openSettings: () -> Void
    private var pollTask: Task<Void, Never>?

    init(settings: AppSettings, appleIntelligenceAvailable: Bool, openSettings: @escaping () -> Void, onFinish: @escaping () -> Void) {
        self.settings = settings
        self.appleIntelligenceAvailable = appleIntelligenceAvailable
        self.openSettings = openSettings
        self.onFinish = onFinish
        state = OnboardingState(
            screenRecordingGranted: ScreenCaptureManager.hasPermission,
            appleIntelligenceAvailable: appleIntelligenceAvailable
        )
        // The permission can be granted in System Settings while the guide is open.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.refresh()
            }
        }
    }

    deinit {
        pollTask?.cancel()
    }

    func select(_ step: OnboardingStep) {
        state.visitedSteps.insert(self.step)
        self.step = step
        refresh()
    }

    func next() {
        guard let index = OnboardingStep.allCases.firstIndex(of: step), index + 1 < OnboardingStep.allCases.count else { return }
        select(OnboardingStep.allCases[index + 1])
    }

    func refresh() {
        state.screenRecordingGranted = ScreenCaptureManager.hasPermission
    }

    func requestScreenRecording() {
        ScreenCaptureManager.requestPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openTranslationLanguages() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAppleIntelligenceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func showSettings() {
        openSettings()
    }

    func finish() {
        pollTask?.cancel()
        onFinish()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(SpyTheme.accentDim).frame(width: 0.75)
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer()
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 20)
        .background(
            ZStack {
                SpyTheme.panel
                LinearGradient(colors: [SpyTheme.accent.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
                Scanlines(opacity: 0.025)
            }
            .ignoresSafeArea()
        )
        .environment(\.colorScheme, .dark)
        .frame(width: 760, height: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("◢ FIELD MANUAL")
                .font(SpyTheme.mono(10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SpyTheme.accent)
                .padding(.bottom, 12)
            ForEach(OnboardingStep.allCases) { step in
                Button {
                    model.select(step)
                } label: {
                    HStack(spacing: 8) {
                        Text(step.code)
                            .font(SpyTheme.mono(10, weight: .bold))
                            .foregroundStyle(model.step == step ? Color.black : SpyTheme.accent)
                        Text(Self.title(of: step))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.step == step ? Color.black : SpyTheme.textPrimary)
                        Spacer()
                        statusChip(model.state.status(of: step), selected: model.step == step)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(model.step == step ? SpyTheme.accent : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 240)
    }

    private func statusChip(_ status: OnboardingStatus, selected: Bool) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .done: return ("OK", SpyTheme.accent)
            case .pending: return ("—", SpyTheme.textSecondary)
            case .optional: return ("OPT", SpyTheme.intel)
            case .unavailable: return ("N/A", SpyTheme.textSecondary)
            }
        }()
        return Text(label)
            .font(SpyTheme.mono(8.5, weight: .bold))
            .foregroundStyle(selected ? Color.black : color)
    }

    @ViewBuilder
    private var content: some View {
        Text(Self.title(of: model.step))
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(SpyTheme.textPrimary)
        switch model.step {
        case .briefing:
            paragraph("Ambient Screen Intelligence watches your screen with you and quietly adds what you would have searched for — a translation, a term, the cause of an error, who is on screen.")
            paragraph("It prefers to show nothing. Most of the time you will not notice it; a card appears only when it is likely to be worth it, and fades after a few seconds.")
            paragraph("Hover a card to keep it and to open its actions. ⌥⌘K opens the archive of everything it has shown you.")
        case .screenAccess:
            paragraph("To see what you see, the app needs Screen Recording permission. Frames stay in memory and are never saved or uploaded.")
            statusLine(model.state.screenRecordingGranted ? "PERMISSION GRANTED" : "PERMISSION REQUIRED", ok: model.state.screenRecordingGranted)
            if !model.state.screenRecordingGranted {
                actionButton("Open Screen Recording settings", action: model.requestScreenRecording)
                paragraph("After enabling the app in System Settings, quit and reopen it.")
            }
        case .translation:
            paragraph("Translation runs on this Mac with Apple's Translation models. Download the languages you want translated in System Settings › General › Language & Region › Translation Languages.")
            Picker("Translate into", selection: Binding(get: { model.settings.targetLanguage }, set: { model.settings.targetLanguage = $0 })) {
                ForEach(AppSettings.supportedTargetLanguages, id: \.self) { code in
                    Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(code)
                }
            }
            .frame(maxWidth: 320)
            actionButton("Open Translation Languages", action: model.openTranslationLanguages)
        case .appleIntelligence:
            paragraph("With Apple Intelligence (macOS 26), the app also explains technical terms, errors and code, adds one-line briefings, names your work sessions and filters borderline cards — all on-device.")
            statusLine(model.state.appleIntelligenceAvailable ? "APPLE INTELLIGENCE AVAILABLE" : "NOT AVAILABLE ON THIS MAC", ok: model.state.appleIntelligenceAvailable)
            if !model.state.appleIntelligenceAvailable {
                actionButton("Open Apple Intelligence settings", action: model.openAppleIntelligenceSettings)
                paragraph("Everything else works without it.")
            }
        case .localKnowledge:
            paragraph("Everything happens on this Mac. The app has no cloud features and never sends screen content anywhere.")
            paragraph("With Apple Intelligence it also guesses what an animal, plant, landmark, dish or product is, who a public figure named on screen is, which film you are watching and the background of a news story. The on-device model cannot see images and knows nothing recent, so these are estimates marked “possibly”.")
            paragraph("Without it, the app still converts units where the pointer rests, expands abbreviations defined earlier on screen and gives hints for common errors.")
            statusLine(model.state.appleIntelligenceAvailable ? "ON-DEVICE KNOWLEDGE READY" : "RULES ONLY (NO APPLE INTELLIGENCE)", ok: model.state.appleIntelligenceAvailable)
            actionButton("Open Settings", action: model.showSettings)
        case .privacy:
            paragraph("• Screen images are never written to disk.")
            paragraph("• Only what a card showed, plus page titles and URLs (if enabled), is archived — on this Mac, excluded from backups, deletable at any time.")
            paragraph("• Password managers, Messages and Photos are excluded; you can add more apps.")
            paragraph("• Pause any time from the menu bar, for 5 minutes, 30 minutes or until tomorrow.")
        }
    }

    private var footer: some View {
        HStack {
            if !model.state.canFinish {
                Text("Screen Recording permission is required to start.")
                    .font(.system(size: 11))
                    .foregroundStyle(SpyTheme.textSecondary)
            }
            Spacer()
            if model.step != OnboardingStep.allCases.last {
                actionButton("Next", action: model.next)
            }
            actionButton("Start", action: model.finish)
                .disabled(!model.state.canFinish)
                .opacity(model.state.canFinish ? 1 : 0.4)
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(SpyTheme.textPrimary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusLine(_ text: LocalizedStringKey, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? SpyTheme.accent : SpyTheme.alert).frame(width: 7, height: 7)
            Text(text)
                .font(SpyTheme.mono(11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(ok ? SpyTheme.accent : SpyTheme.alert)
        }
    }

    private func actionButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SpyTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(SpyTheme.accent.opacity(0.6), lineWidth: 0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func title(of step: OnboardingStep) -> LocalizedStringKey {
        switch step {
        case .briefing: return "Briefing"
        case .screenAccess: return "Screen access"
        case .translation: return "Translation"
        case .appleIntelligence: return "Apple Intelligence"
        case .localKnowledge: return "On-device knowledge"
        case .privacy: return "Privacy"
        }
    }
}

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let makeModel: () -> OnboardingModel

    init(makeModel: @escaping () -> OnboardingModel) {
        self.makeModel = makeModel
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.02, green: 0.05, blue: 0.08, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: makeModel()))
        window.center()
        return window
    }
}
