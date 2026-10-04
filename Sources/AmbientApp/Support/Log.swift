import OSLog

/// Development logging. Never log recognized text verbatim: only counts,
/// lengths and language codes. Use `Console.app` with subsystem filter
/// `com.onishi.AmbientScreenIntelligence` to follow the pipeline.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.onishi.AmbientScreenIntelligence"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let vision = Logger(subsystem: subsystem, category: "vision")
    static let translation = Logger(subsystem: subsystem, category: "translation")
    static let hud = Logger(subsystem: subsystem, category: "hud")
    static let privacy = Logger(subsystem: subsystem, category: "privacy")

    /// Intervals for Instruments (Points of Interest): ocr, translate.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
