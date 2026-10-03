import Foundation

/// Words and short phrases that are so common in user interfaces that
/// translating them would only be noise.
public enum CommonVocabulary {
    public static let uiPhrases: Set<String> = [
        "ok", "cancel", "yes", "no", "done", "close", "open", "save", "save as", "delete", "edit",
        "file", "view", "window", "help", "go", "back", "forward", "next", "previous", "continue",
        "settings", "preferences", "search", "share", "copy", "paste", "cut", "undo", "redo",
        "select all", "new tab", "new window", "sign in", "sign out", "log in", "log out", "sign up",
        "submit", "send", "reply", "reply all", "more", "less", "show more", "show less", "learn more",
        "read more", "home", "menu", "about", "quit", "minimize", "zoom", "format", "tools", "history",
        "bookmarks", "favorites", "downloads", "profile", "account", "accept", "decline", "allow",
        "don't allow", "not now", "remind me later", "skip", "install", "update", "upgrade",
        "safari", "finder", "mail", "messages", "calendar", "notes", "music", "photos", "xcode",
        "terminal", "chrome", "google chrome", "firefox", "slack", "zoom", "keynote", "pages", "numbers",
        "mac", "macos", "ai", "apple", "google", "youtube", "github", "twitter", "x", "facebook",
        "instagram", "linkedin", "accept all cookies", "reject all", "cookie settings", "privacy policy",
        "terms of service", "all rights reserved", "loading...", "loading", "untitled", "today",
        "yesterday", "tomorrow", "inbox", "sent", "drafts", "trash", "archive", "spam"
    ]

    public static func isCommonPhrase(_ text: String) -> Bool {
        let trimmed = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".…:!?•·|>"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return uiPhrases.contains(trimmed)
    }
}
