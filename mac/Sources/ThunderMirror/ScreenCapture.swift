import Foundation
import ScreenCaptureKit
import CoreGraphics
import Logging

/// Screen capture delegate for receiving frames from ScreenCaptureKit
///
/// This class handles real screen capture using macOS ScreenCaptureKit framework.
/// It captures the main display at 60 fps and delivers RGBA frames.
@available(macOS 12.3, *)
class ScreenCapture: NSObject {
    enum CaptureDisplaySelection {
        case main
        case secondary
        case displayID(CGDirectDisplayID)
    }

    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private let logger = Logger(label: "com.thundermirror.capture")
    
    /// Current display resolution
    private(set) var width: UInt16 = 0
    private(set) var height: UInt16 = 0
    
    /// Frame callback - called for each captured frame
    var onFrame: ((Data, UInt16, UInt16) -> Void)?
    
    /// Resolution change callback
    var onResolutionChange: ((UInt16, UInt16) -> Void)?
    
    /// Whether to capture at native (physical pixel) resolution. Default true for Retina quality.
    var captureAtNativeResolution: Bool = true

    /// Start capturing the screen
    /// - Throws: Error if capture cannot be started
    func startCapture(selection: CaptureDisplaySelection = .main) async throws {
        // Check for Screen Recording permission
        let hasPermission = try await checkPermission()
        guard hasPermission else {
            throw ScreenCaptureError.permissionDenied
        }
        
        // Get available displays
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        let displays = content.displays
        guard !displays.isEmpty else {
            throw ScreenCaptureError.noDisplayFound
        }

        // Choose display.
        let mainID = CGMainDisplayID()
        let display: SCDisplay
        switch selection {
        case .main:
            display = displays.first(where: { $0.displayID == mainID }) ?? displays.first!
        case .displayID(let desiredID):
            display = displays.first(where: { $0.displayID == desiredID }) ?? displays.first!
            if display.displayID != desiredID {
                logger.warning("Requested displayID \(desiredID) not found; using displayID \(display.displayID) instead.")
            }
        case .secondary:
            let secondaryDisplays = displays.filter { $0.displayID != mainID }
            if let best = secondaryDisplays.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
                display = best
            } else {
                logger.warning("No secondary display found; falling back to main displayID \(mainID).")
                display = displays.first(where: { $0.displayID == mainID }) ?? displays.first!
            }
        }
        
        // Query physical pixel dimensions (Retina-aware).
        let nativeWidth = Int(CGDisplayPixelsWide(display.displayID))
        let nativeHeight = Int(CGDisplayPixelsHigh(display.displayID))
        let logicalWidth = display.width
        let logicalHeight = display.height

        let captureWidth: Int
        let captureHeight: Int
        if captureAtNativeResolution && nativeWidth > 0 && nativeHeight > 0 {
            captureWidth = nativeWidth
            captureHeight = nativeHeight
            logger.info("Using displayID \(display.displayID): \(captureWidth)x\(captureHeight) (native pixels)")
        } else {
            captureWidth = logicalWidth
            captureHeight = logicalHeight
            logger.info("Using displayID \(display.displayID): \(captureWidth)x\(captureHeight) (logical points)")
        }
        
        // Store initial resolution
        width = UInt16(captureWidth)
        height = UInt16(captureHeight)
        
        // Configure stream
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        let config = SCStreamConfiguration()
        config.width = captureWidth
        config.height = captureHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 fps
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA // BGRA format (will convert to RGBA)
        config.showsCursor = true
        
        // Create stream output handler
        streamOutput = StreamOutput()
        streamOutput?.onFrame = { [weak self] sampleBuffer in
            self?.handleFrame(sampleBuffer)
        }
        
        // Create and start stream
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        guard let stream = stream, let output = streamOutput else {
            throw ScreenCaptureError.streamCreationFailed
        }
        
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.thundermirror.capture.frames"))
        try await stream.startCapture()
        
        logger.info("Screen capture started at \(width)x\(height) @ 60fps")
    }
    
    /// Stop capturing
    func stopCapture() async {
        do {
            try await stream?.stopCapture()
        } catch {
            logger.warning("Error stopping capture: \(error)")
        }
        stream = nil
        streamOutput = nil
        logger.info("Screen capture stopped")
    }
    
    /// Check if Screen Recording permission is granted
    private func checkPermission() async throws -> Bool {
        // CGPreflightScreenCaptureAccess checks without prompting
        // CGRequestScreenCaptureAccess will prompt if needed
        
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        
        // Request access (this will show the system dialog)
        logger.info("Requesting Screen Recording permission...")
        let granted = CGRequestScreenCaptureAccess()
        
        if !granted {
            logger.error("Screen Recording permission denied")
            logger.error("Please grant access in System Preferences > Privacy & Security > Screen Recording")
        }
        
        return granted
    }
    
    /// Handle a captured frame
    private func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return
        }
        
        // Check for resolution change
        let newWidth = UInt16(pixelWidth)
        let newHeight = UInt16(pixelHeight)
        
        if newWidth != width || newHeight != height {
            width = newWidth
            height = newHeight
            logger.info("Resolution changed to \(width)x\(height)")
            onResolutionChange?(width, height)
        }
        
        // Convert BGRA to RGBA
        let pixelCount = pixelWidth * pixelHeight
        var rgbaData = Data(count: pixelCount * 4)
        
        rgbaData.withUnsafeMutableBytes { rgbaPtr in
            guard let rgbaDest = rgbaPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            
            let bgraSource = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            for y in 0..<pixelHeight {
                let rowOffset = y * bytesPerRow
                let destRowOffset = y * pixelWidth * 4
                
                for x in 0..<pixelWidth {
                    let srcOffset = rowOffset + x * 4
                    let destOffset = destRowOffset + x * 4
                    
                    // BGRA -> RGBA
                    rgbaDest[destOffset + 0] = bgraSource[srcOffset + 2] // R
                    rgbaDest[destOffset + 1] = bgraSource[srcOffset + 1] // G
                    rgbaDest[destOffset + 2] = bgraSource[srcOffset + 0] // B
                    rgbaDest[destOffset + 3] = bgraSource[srcOffset + 3] // A
                }
            }
        }
        
        onFrame?(rgbaData, width, height)
    }
}

/// Stream output handler for receiving screen capture frames
@available(macOS 12.3, *)
private class StreamOutput: NSObject, SCStreamOutput {
    var onFrame: ((CMSampleBuffer) -> Void)?
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        onFrame?(sampleBuffer)
    }
}

/// Screen capture errors
enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case streamCreationFailed
    case captureError(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission denied. Please grant access in System Preferences > Privacy & Security > Screen Recording"
        case .noDisplayFound:
            return "No display found to capture"
        case .streamCreationFailed:
            return "Failed to create screen capture stream"
        case .captureError(let message):
            return "Capture error: \(message)"
        }
    }
}

