import Foundation

/// The work being watched (set by `ContextIntelCoordinator`), read by the
/// pipeline to recognize characters / performers named on screen.
final class MediaContext: @unchecked Sendable {
    private let lock = NSLock()
    private var cast: [CastMember] = []
    private var workTitle: String?

    func update(workTitle: String?, cast: [CastMember]) {
        lock.withLock {
            self.workTitle = workTitle
            self.cast = cast
        }
    }

    var current: (title: String?, cast: [CastMember]) {
        lock.withLock { (workTitle, cast) }
    }
}
