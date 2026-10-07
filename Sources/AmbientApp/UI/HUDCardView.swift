import SwiftUI

/// The intel card. All animated values are passed in, so the same view can be
/// rendered static (for measuring) or driven by a `TimelineView`.
struct HUDCardView: View {
    let message: HUDMessage
    let briefing: BriefingState
    /// 0...1 decode progress of the translation.
    var decodeProgress: Double = 1
    var tick: Int = 0
    var caretVisible: Bool = true
    /// 0...1 position of the scan sweep, nil when finished.
    var sweep: Double?
    /// Shows the More actions (only while the card is interactive).
    var showsActions = false
    var onAction: ((HUDAction) -> Void)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 9) {
                metaRow
                Text(message.original)
                    .font(SpyTheme.mono(11))
                    .foregroundStyle(SpyTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                divider
                translation
                if briefing != .none {
                    briefingRow
                }
                if let seen = reappearanceLabel {
                    Text("SEEN ▸ \(seen)")
                        .font(SpyTheme.mono(9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(SpyTheme.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 13)
            if showsActions {
                actionBar
            }
        }
        .frame(width: SpyTheme.cardWidth, alignment: .leading)
        .background(background)
        .overlay(sweepOverlay)
        .overlay(
            Rectangle().strokeBorder(SpyTheme.accentDim, lineWidth: 0.75)
        )
        .overlay(
            CornerBrackets(length: SpyTheme.cornerTick)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                .padding(-3)
        )
        .compositingGroup()
        .shadow(color: SpyTheme.accent.opacity(0.18), radius: 14)
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.title): \(message.detail)")
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            switch message.kind {
            case .securityWarning:
                EmptyView()
            case .qrCode, .conversion:
                actionButton("COPY", .copy)
            case .regionSummary:
                actionButton("COPY", .copy)
                actionButton("NOT USEFUL", .notUseful)
            case .noIntel:
                EmptyView()
            case .resume:
                actionButton("SESSIONS", .openArchive)
            case .mediaInfo, .cast:
                actionButton("WEB", .webSearch)
                actionButton("WIKI", .wikipedia)
                actionButton("NOT USEFUL", .notUseful)
            case .newsContext:
                actionButton("WEB", .webSearch)
                actionButton("NOT USEFUL", .notUseful)
            case .identification, .publicFigure:
                actionButton("COPY", .copy)
                actionButton("WEB", .webSearch)
                actionButton("WIKI", .wikipedia)
                actionButton("NOT USEFUL", .notUseful)
            case .translation, .explanation, .errorAnalysis, .codeSummary:
                actionButton("COPY", .copy)
                actionButton("ARCHIVE", .openArchive)
                actionButton("NOT USEFUL", .notUseful)
            }
            switch message.kind {
            case .explanation:
                actionButton("KNOWN", .markKnown)
            case .translation:
                if let language = message.sourceLanguage {
                    actionButton("MUTE \(LanguageCode.base(language).uppercased())", .skipLanguage)
                }
            case .errorAnalysis, .codeSummary, .securityWarning, .qrCode, .resume, .identification, .publicFigure,
                 .mediaInfo, .cast, .newsContext, .conversion, .regionSummary, .noIntel:
                EmptyView()
            }
            Spacer(minLength: 0)
            actionButton("✕", .close)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(SpyTheme.accent.opacity(0.07))
        .overlay(alignment: .top) {
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
        }
    }

    private func actionButton(_ title: String, _ action: HUDAction) -> some View {
        Button {
            onAction?(action)
        } label: {
            Text(title)
                .font(SpyTheme.mono(9, weight: .bold))
                .tracking(1)
                .foregroundStyle(action == .close ? SpyTheme.textSecondary : SpyTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(Rectangle().strokeBorder(SpyTheme.accentDim, lineWidth: 0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(action.help)
    }

    private var headerTitle: String {
        switch message.kind {
        case .translation: return "INTERCEPT // LINGUISTIC"
        case .explanation: return "INTEL // TERMINOLOGY"
        case .errorAnalysis: return "ALERT // FAULT ANALYSIS"
        case .codeSummary: return "INTEL // CODE ANALYSIS"
        case .securityWarning: return "⚠ WARNING // EXPOSURE RISK"
        case .qrCode: return "SCAN // QR PAYLOAD"
        case .resume: return "RESUME // LAST OPERATION"
        case .identification: return "TARGET // IDENTIFICATION"
        case .publicFigure: return "DOSSIER // PUBLIC FIGURE"
        case .mediaInfo: return "DOSSIER // FEATURE"
        case .cast: return "CAST // ON SCREEN"
        case .newsContext: return "BRIEFING // BACKGROUND"
        case .conversion: return "INTEL // CONVERSION"
        case .regionSummary: return "INTEL // TARGET ANALYSIS"
        case .noIntel: return "SCAN // NO INTEL"
        }
    }

    private var chipTitle: String {
        switch message.kind {
        case .translation: return HUDCodename.route(source: message.sourceLanguage, target: message.targetLanguage)
        case .explanation: return "TERM"
        case .errorAnalysis: return "FAULT"
        case .codeSummary: return "CODE"
        case .securityWarning: return "SHARING"
        case .qrCode: return "QR"
        case .resume: return "RESUME"
        case .identification: return "ID"
        case .publicFigure: return "DOSSIER"
        case .mediaInfo: return "FEATURE"
        case .cast: return "CAST"
        case .newsContext: return "NEWS"
        case .conversion: return "UNITS"
        case .regionSummary: return "TARGET"
        case .noIntel: return "NULL"
        }
    }

    /// Faults and exposure warnings use the alert color.
    private var tint: Color {
        switch message.kind {
        case .errorAnalysis, .securityWarning: return SpyTheme.alert
        case .resume, .publicFigure, .mediaInfo, .cast, .newsContext: return SpyTheme.intel
        case .translation, .explanation, .codeSummary, .qrCode, .identification, .conversion, .regionSummary, .noIntel:
            return SpyTheme.accent
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("◢")
                .foregroundStyle(tint)
            Text(headerTitle)
                .foregroundStyle(tint.opacity(0.9))
            Spacer(minLength: 8)
            Circle()
                .fill(SpyTheme.alert)
                .frame(width: 5, height: 5)
                .opacity(caretVisible ? 1 : 0.35)
            Text(Self.timeFormatter.string(from: message.capturedAt))
                .foregroundStyle(SpyTheme.textSecondary)
        }
        .font(SpyTheme.mono(9.5, weight: .semibold))
        .tracking(1.4)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
        }
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Text(HUDCodename.targetCode(for: message.id))
                .foregroundStyle(SpyTheme.textSecondary)
            Text(chipTitle)
                .foregroundStyle(SpyTheme.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(Rectangle().strokeBorder(SpyTheme.accentDim, lineWidth: 0.75))
            Text(message.title.uppercased())
                .foregroundStyle(SpyTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let confidence = message.confidence {
                ConfidenceMeter(confidence: confidence)
            }
        }
        .font(SpyTheme.mono(9, weight: .semibold))
        .tracking(0.8)
    }

    private var divider: some View {
        HStack(spacing: 4) {
            Rectangle().fill(SpyTheme.accentDim).frame(height: 0.75)
            Text("DECRYPTED")
                .font(SpyTheme.mono(7.5, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(SpyTheme.accent.opacity(0.7))
            Rectangle().fill(SpyTheme.accentDim).frame(width: 18, height: 0.75)
        }
    }

    private var translation: some View {
        // The final text is laid out invisibly so the card never changes size
        // while the scrambled frames (which have different glyph widths) play.
        Text(message.detail)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(6)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .overlay(alignment: .topLeading) {
                Text(DecodeEffect.frame(of: message.detail, progress: decodeProgress, tick: tick))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(decodeProgress >= 1 ? SpyTheme.textPrimary : SpyTheme.accent)
                    .lineLimit(6)
                    .shadow(color: SpyTheme.accent.opacity(decodeProgress >= 1 ? 0.25 : 0.6), radius: 6)
            }
    }

    private var reappearanceLabel: String? {
        guard let seen = message.previouslySeen,
              let days = Reappearance.daysSince(seen, now: message.capturedAt) else { return nil }
        return Reappearance.label(days: days, language: message.targetLanguage ?? "en")
    }

    private var briefingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("BRIEF ▸")
                .font(SpyTheme.mono(9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(SpyTheme.intel)
            switch briefing {
            case .ready(let text):
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SpyTheme.intel.opacity(0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            case .pending, .none:
                Text("ANALYZING" + (caretVisible ? " ▮" : "  "))
                    .font(SpyTheme.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(SpyTheme.intel.opacity(0.7))
            }
        }
        .padding(.top, 2)
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(SpyTheme.panel.opacity(0.82))
            LinearGradient(colors: [SpyTheme.accent.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
            Scanlines()
        }
    }

    @ViewBuilder
    private var sweepOverlay: some View {
        if let sweep {
            GeometryReader { proxy in
                LinearGradient(colors: [.clear, SpyTheme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                    .offset(y: proxy.size.height * sweep - 18)
            }
            .clipped()
            .allowsHitTesting(false)
        }
    }
}

/// Segmented confidence bar: ▮▮▮▮▮▮▮▯▯▯ 97%
struct ConfidenceMeter: View {
    let confidence: Double

    var body: some View {
        let filled = HUDCodename.meterSegments(confidence: confidence)
        HStack(spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
                Rectangle()
                    .fill(index < filled ? SpyTheme.accent : SpyTheme.accent.opacity(0.18))
                    .frame(width: 3, height: 7)
            }
            Text("\(Int((confidence * 100).rounded()))%")
                .foregroundStyle(SpyTheme.accent)
                .padding(.leading, 3)
        }
    }
}

/// What the user can do from the HUD's More actions.
enum HUDAction: Equatable {
    case copy
    case openArchive
    case notUseful
    case skipLanguage
    case markKnown
    case webSearch
    case wikipedia
    case close

    var help: String {
        switch self {
        case .copy: return "Copy the translation"
        case .openArchive: return "Open in the archive"
        case .notUseful: return "Show less of this"
        case .skipLanguage: return "Never translate this language"
        case .markKnown: return "I know this term — don't explain it again"
        case .webSearch: return "Search the web in your browser"
        case .wikipedia: return "Open Wikipedia in your browser"
        case .close: return "Close"
        }
    }
}
