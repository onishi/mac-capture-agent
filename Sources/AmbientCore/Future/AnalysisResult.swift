import Foundation

/// Output of an `AIProvider` (local or cloud). The provider protocol itself
/// lives in the app layer because it takes a `CGImage`.
public struct AnalysisResult: Sendable, Equatable {
    public let actions: [RoutedAction]
    public let summary: String?
    public let entities: [String]

    public init(actions: [RoutedAction], summary: String? = nil, entities: [String] = []) {
        self.actions = actions
        self.summary = summary
        self.entities = entities
    }
}
