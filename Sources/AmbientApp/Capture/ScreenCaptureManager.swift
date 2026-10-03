import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplay
}

/// Wraps `SCStream`: permission checks, display selection, start/stop, and
/// delivery of frames through an `AsyncStream`.
///
/// Frames are buffered with `.bufferingNewest(1)`, so a slow consumer never
/// builds up a backlog — it simply always gets the latest screen state.
final class ScreenCaptureManager: NSObject, @unchecked Sendable {
    struct Options: Sendable {
        var preferredDisplayID: CGDirectDisplayID?
        var framesPerSecond: Int
        /// Apps whose windows are removed from the captured image entirely.
        var excludedBundleIdentifiers: Set<String>
        /// Captured images are scaled so that their longest side does not exceed this.
        var maximumDimension: Int = 3_000
    }

    private let sampleQueue = DispatchQueue(label: "ambient.capture.samples", qos: .utility)
    private let lock = NSLock()
    private var stream: SCStream?
    private var continuation: AsyncStream<CapturedFrame>.Continuation?
    private var currentDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private var hasLoggedFirstFrame = false

    // MARK: Permission

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (only the first time) and returns the current state.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    // MARK: Displays

    func availableDisplays() async throws -> [SCDisplay] {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
    }

    // MARK: Lifecycle

    /// Starts capturing and returns the frame stream together with the captured display.
    func start(options: Options) async throws -> (frames: AsyncStream<CapturedFrame>, displayID: CGDirectDisplayID) {
        await stop()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            Log.capture.error("Shareable content unavailable: \(error.localizedDescription, privacy: .public)")
            throw ScreenCaptureError.permissionDenied
        }

        let display = content.displays.first { $0.displayID == options.preferredDisplayID }
            ?? content.displays.first { $0.displayID == CGMainDisplayID() }
            ?? content.displays.first
        guard let display else { throw ScreenCaptureError.noDisplay }

        // Exclude our own HUD (so we never OCR ourselves) and sensitive apps.
        let ownBundleID = Bundle.main.bundleIdentifier
        let excludedApps = content.applications.filter {
            $0.bundleIdentifier == ownBundleID || options.excludedBundleIdentifiers.contains($0.bundleIdentifier)
        }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        var width = Double(display.width) * scale
        var height = Double(display.height) * scale
        let longest = max(width, height)
        if longest > Double(options.maximumDimension) {
            let factor = Double(options.maximumDimension) / longest
            width *= factor
            height *= factor
        }
        configuration.width = max(1, Int(width))
        configuration.height = max(1, Int(height))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, options.framesPerSecond)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        let (frames, continuation) = AsyncStream.makeStream(of: CapturedFrame.self, bufferingPolicy: .bufferingNewest(1))
        lock.withLock {
            self.stream = stream
            self.continuation = continuation
            self.currentDisplayID = display.displayID
            self.hasLoggedFirstFrame = false
        }

        do {
            try await stream.startCapture()
        } catch {
            lock.withLock {
                self.stream = nil
                self.continuation = nil
            }
            continuation.finish()
            throw error
        }
        Log.capture.info("Capture started: display \(display.displayID), \(configuration.width)x\(configuration.height) @ \(options.framesPerSecond) fps, excluded apps: \(excludedApps.count)")
        return (frames, display.displayID)
    }

    func stop() async {
        let (stream, continuation) = lock.withLock { () -> (SCStream?, AsyncStream<CapturedFrame>.Continuation?) in
            defer {
                self.stream = nil
                self.continuation = nil
            }
            return (self.stream, self.continuation)
        }
        continuation?.finish()
        guard let stream else { return }
        do {
            try await stream.stopCapture()
            Log.capture.info("Capture stopped")
        } catch {
            Log.capture.error("Failed to stop capture: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureManager: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Only complete frames carry new pixels; idle/blank frames are skipped.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }

        let (continuation, displayID, isFirst) = lock.withLock { () -> (AsyncStream<CapturedFrame>.Continuation?, CGDirectDisplayID, Bool) in
            let first = !hasLoggedFirstFrame
            hasLoggedFirstFrame = true
            return (self.continuation, currentDisplayID, first)
        }
        if isFirst { Log.capture.debug("Screen captured (first frame)") }
        continuation?.yield(CapturedFrame(
            pixelBuffer: pixelBuffer,
            timestamp: ProcessInfo.processInfo.systemUptime,
            displayID: displayID
        ))
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureManager: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.capture.error("Stream stopped with error: \(error.localizedDescription, privacy: .public)")
        let continuation = lock.withLock { () -> AsyncStream<CapturedFrame>.Continuation? in
            defer {
                self.stream = nil
                self.continuation = nil
            }
            return self.continuation
        }
        continuation?.finish()
    }
}
