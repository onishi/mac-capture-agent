import Foundation

/// Everything the router knows about the current moment on screen.
public struct AnalysisContext: Sendable, Equatable {
    public let appName: String?
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let textRegions: [RecognizedTextRegion]
    public let visualCategories: [VisualCategory]

    public init(
        appName: String?,
        bundleIdentifier: String? = nil,
        windowTitle: String?,
        textRegions: [RecognizedTextRegion],
        visualCategories: [VisualCategory]
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.textRegions = textRegions
        self.visualCategories = visualCategories
    }
}
