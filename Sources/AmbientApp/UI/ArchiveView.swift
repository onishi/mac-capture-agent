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
            tabBar
            if model.tab == .records {
                queryField
            }
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
            switch model.tab {
            case .records: results
            case .sessions: sessionsList
            case .today: todayView
            }
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

    private static let rangeFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(ArchiveTab.allCases, id: \.self) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(SpyTheme.mono(10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(model.tab == tab ? Color.black : SpyTheme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(model.tab == tab ? SpyTheme.accent : Color.clear)
                        .overlay(Rectangle().strokeBorder(SpyTheme.accentDim, lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var sessionsList: some View {
        if model.sessions.isEmpty {
            emptyState(title: "NO SESSIONS YET", detail: "Work sessions appear after a few minutes of activity (titles and URLs only).")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: WorkSessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.title ?? "Session")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SpyTheme.textPrimary)
                Spacer()
                Text("\(Int((session.activeSeconds / 60).rounded())) MIN")
                    .font(SpyTheme.mono(10, weight: .bold))
                    .foregroundStyle(SpyTheme.accent)
            }
            Text("\(Self.rangeFormatter.string(from: session.start, to: session.end)) · \(session.applications.prefix(4).joined(separator: ", "))")
                .font(SpyTheme.mono(9.5, weight: .semibold))
                .foregroundStyle(SpyTheme.textSecondary)
            ForEach(session.bookmarks) { bookmark in
                Button {
                    if let url = bookmark.url { model.openPage(url) }
                } label: {
                    HStack(spacing: 6) {
                        Text("★").foregroundStyle(SpyTheme.intel)
                        Text(bookmark.title ?? bookmark.url?.absoluteString ?? "—")
                            .foregroundStyle(SpyTheme.textPrimary.opacity(0.9))
                            .lineLimit(1)
                        if let url = bookmark.url {
                            Text(URLSanitizer.displayHost(url))
                                .foregroundStyle(SpyTheme.textSecondary)
                        }
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .disabled(bookmark.url == nil)
            }
            ForEach(session.topPages.filter { page in !session.bookmarks.contains { $0.title == page } }.prefix(3), id: \.self) { page in
                Text("· \(page)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(SpyTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpyTheme.accent.opacity(0.08)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var todayView: some View {
        if model.themes.isEmpty {
            emptyState(title: "NOTHING LOGGED TODAY", detail: "Today's themes appear once work sessions have been recorded.")
        } else {
            let maximum = Double(model.themes.map(\.minutes).max() ?? 1)
            VStack(alignment: .leading, spacing: 12) {
                Text("TODAY'S MAIN THEMES")
                    .font(SpyTheme.mono(10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(SpyTheme.accent)
                ForEach(model.themes, id: \.name) { theme in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(theme.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SpyTheme.textPrimary)
                            Spacer()
                            Text("\(theme.minutes) MIN")
                                .font(SpyTheme.mono(10, weight: .bold))
                                .foregroundStyle(SpyTheme.accent)
                        }
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(SpyTheme.accent.opacity(0.75))
                                .frame(width: max(2, proxy.size.width * Double(theme.minutes) / maximum))
                        }
                        .frame(height: 6)
                        .background(SpyTheme.accent.opacity(0.12))
                    }
                }
                Spacer()
            }
            .padding(18)
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Text(title)
                .font(SpyTheme.mono(13, weight: .bold))
                .tracking(3)
                .foregroundStyle(SpyTheme.accent.opacity(0.6))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(SpyTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
