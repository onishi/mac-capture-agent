import Foundation

/// What VoiceOver reads when a card appears. The card itself is click-through
/// and fades on its own, so the content is announced once, compactly.
public enum AccessibilityAnnouncement {
    /// Collapses whitespace and line breaks and truncates each part.
    /// Returns nil when there is nothing worth reading.
    public static func parts(title: String, detail: String, limit: Int = 160) -> (title: String, detail: String)? {
        let cleanTitle = clean(title, limit: 60)
        let cleanDetail = clean(detail, limit: limit)
        guard !cleanTitle.isEmpty || !cleanDetail.isEmpty else { return nil }
        return (cleanTitle, cleanDetail)
    }

    static func clean(_ text: String, limit: Int) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
