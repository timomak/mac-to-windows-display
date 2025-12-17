import Foundation
import ScreenCaptureKit
import CoreGraphics
import Logging

/// Screen capture delegate for receiving frames from ScreenCaptureKit
///
/// This class handles real screen capture using macOS ScreenCaptureKit framework.
/// It captures the main display at 60 fps and delivers BGRA frames (native format for H.264 encoding).
@available(macOS 12.3, *)
class ScreenCapture: NSObject {
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private let logger = Logger(label: "com.thundermirror.capture")
    
    /// Current display resolution
    private(set) var width: UInt16 = 0
    private(set) var height: UInt16 = 0
    
    /// Frame callback - called for each captured frame (BGRA format by default)
    var onFrame: ((Data, UInt16, UInt16) -> Void)?
    
    /// Resolution change callback
    var onResolutionChange: ((UInt16, UInt16) -> Void)?
    
    /// Whether to capture at native (physical pixel) resolution. Default false for better performance.
    var captureAtNativeResolution: Bool = false
    
    /// Maximum width in pixels. If source is wider, scales down maintaining aspect ratio.
    var maxWidth: Int?
    
    /// Start capturing the screen
    /// - Throws: Error if capture cannot be started
    func startCapture() async throws {
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
        
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }
        
        // Query physical pixel dimensions (Retina-aware)
        let displayMode = CGDisplayCopyDisplayMode(display.displayID)
        let nativeWidth = displayMode?.pixelWidth ?? display.width
        let nativeHeight = displayMode?.pixelHeight ?? display.height
        let logicalWidth = display.width
        let logicalHeight = display.height
        
        var captureWidth: Int
        var captureHeight: Int
        
        // Determine target resolution based on maxWidth setting
        // If maxWidth is set and larger than logical, use native and scale down
        // If maxWidth is Native (9999) or larger than native, use full native
        let effectiveMaxWidth = maxWidth ?? 9999
        
        if effectiveMaxWidth >= nativeWidth || effectiveMaxWidth >= 9999 {
            // Use full native resolution
            captureWidth = nativeWidth
            captureHeight = nativeHeight
            logger.info("Capture: \(captureWidth)x\(captureHeight) (full native)")
        } else if effectiveMaxWidth > logicalWidth {
            // Use native but scale to maxWidth
            let aspectRatio = Double(nativeHeight) / Double(nativeWidth)
            captureWidth = effectiveMaxWidth
            captureHeight = Int(Double(effectiveMaxWidth) * aspectRatio)
            // Ensure dimensions are even (required for H.264)
            captureWidth = (captureWidth / 2) * 2
            captureHeight = (captureHeight / 2) * 2
            logger.info("Capture: \(captureWidth)x\(captureHeight) (scaled from native)")
        } else if effectiveMaxWidth >= logicalWidth {
            // Use logical resolution
            captureWidth = logicalWidth
            captureHeight = logicalHeight
            logger.info("Capture: \(captureWidth)x\(captureHeight) (logical)")
        } else {
            // Scale down from logical
            let aspectRatio = Double(logicalHeight) / Double(logicalWidth)
            captureWidth = effectiveMaxWidth
            captureHeight = Int(Double(effectiveMaxWidth) * aspectRatio)
            captureWidth = (captureWidth / 2) * 2
            captureHeight = (captureHeight / 2) * 2
            logger.info("Capture: \(captureWidth)x\(captureHeight) (scaled from logical)")
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
        config.pixelFormat = kCVPixelFormatType_32BGRA // BGRA format (optimal for H.264)
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
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        
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
        
        // Pass BGRA directly (optimal for H.264 encoding - no conversion needed!)
        let pixelCount = pixelWidth * pixelHeight
        var bgraData = Data(count: pixelCount * 4)
        
        bgraData.withUnsafeMutableBytes { destPtr in
            guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let src = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            // Copy row by row to handle bytesPerRow padding
            for y in 0..<pixelHeight {
                let srcOffset = y * bytesPerRow
                let dstOffset = y * pixelWidth * 4
                memcpy(dest.advanced(by: dstOffset), src.advanced(by: srcOffset), pixelWidth * 4)
            }
        }
        
        onFrame?(bgraData, width, height)
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
