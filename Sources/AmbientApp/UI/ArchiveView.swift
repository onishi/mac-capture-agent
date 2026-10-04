import SwiftUI

/// "ARCHIVE // VISUAL MEMORY" — search everything the HUD has surfaced.
struct ArchiveView: View {
    @ObservedObject var model: ArchiveViewModel
    @FocusState private var queryFocused: Bool
    @State private var hoveredID: UUID?
    @State private var confirmPurge = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            queryField
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
            results
            footer
        }
        .background(background)
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            queryFocused = true
            model.refresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Text("◢").foregroundStyle(SpyTheme.accent)
            Text("ARCHIVE // VISUAL MEMORY")
                .foregroundStyle(SpyTheme.accent)
            Spacer()
            Circle().fill(model.memoryEnabled() ? SpyTheme.accent : SpyTheme.alert).frame(width: 6, height: 6)
            Text(model.memoryEnabled() ? "RECORDING" : "RECORDING OFF")
                .foregroundStyle(SpyTheme.textSecondary)
        }
        .font(SpyTheme.mono(10, weight: .semibold))
        .tracking(1.6)
        .padding(.horizontal, 18)
        .padding(.top, 30)   // room for the transparent title bar
        .padding(.bottom, 10)
    }

    private var queryField: some View {
        HStack(spacing: 10) {
            Text("QUERY ▸")
                .font(SpyTheme.mono(12, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(SpyTheme.accent)
            TextField("", text: $model.query, prompt: Text("昨日のフランス語 · museum yesterday · さっきの英語").foregroundColor(SpyTheme.textSecondary.opacity(0.6)))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SpyTheme.textPrimary)
                .focused($queryFocused)
            if model.isSearching {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(SpyTheme.accent.opacity(0.06))
    }

    @ViewBuilder
    private var results: some View {
        if model.results.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Text(model.totalRecords == 0 ? "ARCHIVE EMPTY" : "NO MATCHING RECORDS")
                    .font(SpyTheme.mono(13, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(SpyTheme.accent.opacity(0.6))
                Text(model.totalRecords == 0
                     ? "Intel shown in the HUD is archived here, on this Mac only."
                     : "Try a time (昨日, today) or a language (フランス語, German).")
                    .font(.system(size: 12))
                    .foregroundStyle(SpyTheme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.results) { result in
                        row(result.entry)
                    }
                }
            }
        }
    }

    private func row(_ entry: VisualMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .foregroundStyle(SpyTheme.textSecondary)
                Text(Self.routeLabel(entry))
                    .foregroundStyle(SpyTheme.accent)
                Text((entry.application ?? "—").uppercased())
                    .foregroundStyle(SpyTheme.textSecondary.opacity(0.8))
                    .lineLimit(1)
            }
            .font(SpyTheme.mono(9.5, weight: .semibold))
            .tracking(0.6)
            .frame(width: 92, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.translation)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(SpyTheme.textPrimary)
                    .lineLimit(3)
                Text(entry.original)
                    .font(SpyTheme.mono(10.5))
                    .foregroundStyle(SpyTheme.textSecondary)
                    .lineLimit(2)
                if let briefing = entry.briefing {
                    Text("BRIEF ▸ \(briefing)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SpyTheme.intel)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if model.copiedID == entry.id {
                Text("COPIED")
                    .font(SpyTheme.mono(9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SpyTheme.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(hoveredID == entry.id ? SpyTheme.accent.opacity(0.07) : .clear)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(SpyTheme.accent)
                .frame(width: 2)
                .opacity(hoveredID == entry.id ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpyTheme.accent.opacity(0.08)).frame(height: 0.5)
        }
        .contentShape(Rectangle())
        .onHover { inside in hoveredID = inside ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }
        .onTapGesture { model.open(entry) }
        .help("Click to copy the translation")
    }

    private static func routeLabel(_ entry: VisualMemoryEntry) -> String {
        switch entry.kind {
        case .translation: return HUDCodename.route(source: entry.sourceLanguage, target: entry.targetLanguage)
        case .explanation: return "TERM"
        case .errorAnalysis: return "FAULT"
        case .codeSummary: return "CODE"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(model.totalRecords) RECORDS · RETENTION \(model.retentionDays())D · LOCAL ONLY")
                .foregroundStyle(SpyTheme.textSecondary)
            Spacer()
            Text("⌥⌘K")
                .foregroundStyle(SpyTheme.accent.opacity(0.7))
            Button {
                confirmPurge = true
            } label: {
                Text("PURGE")
                    .foregroundStyle(SpyTheme.alert)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .overlay(Rectangle().strokeBorder(SpyTheme.alert.opacity(0.6), lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .disabled(model.totalRecords == 0)
            .confirmationDialog("Delete every archived record?", isPresented: $confirmPurge) {
                Button("Purge Archive", role: .destructive) { model.purge() }
            }
        }
        .font(SpyTheme.mono(9.5, weight: .semibold))
        .tracking(1.2)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(SpyTheme.accent.opacity(0.05))
        .overlay(alignment: .top) {
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
        }
    }

    private var background: some View {
        ZStack {
            SpyTheme.panel
            LinearGradient(colors: [SpyTheme.accent.opacity(0.06), .clear], startPoint: .top, endPoint: .center)
            Scanlines(opacity: 0.025)
        }
        .ignoresSafeArea()
    }
}
