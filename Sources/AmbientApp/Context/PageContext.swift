import Foundation

/// The page currently in front (URL when known), shared between the activity
/// tracker (writer, main thread) and the analysis pipeline (reader).
final class PageContext: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?

    var currentURL: URL? {
        lock.withLock { url }
    }

    func update(url: URL?) {
        lock.withLock { self.url = url }
    }
}
