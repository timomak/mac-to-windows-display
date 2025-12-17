import ArgumentParser
import Foundation
import Logging
import ScreenCaptureKit
import VideoToolbox
import CoreGraphics

/// ThunderMirror Mac Sender CLI
///
/// Captures the Mac screen and streams it to a Windows receiver over Thunderbolt.
@main
struct ThunderMirror: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ThunderMirror",
        abstract: "Stream Mac display to Windows over Thunderbolt",
        version: "0.3.0"
    )

    @Option(name: .shortAndLong, help: "Windows receiver IP address")
    var targetIP: String = "192.168.50.2"

    @Option(name: .shortAndLong, help: "Streaming port")
    var port: UInt16 = 9999

    @Option(name: .long, help: "Streaming mode (mirror or extend)")
    var mode: StreamMode = .mirror

    @Flag(
        name: .long,
        help: "Attempt experimental virtual display creation when using --mode extend (requires building with -Xswiftc -DEXTEND_EXPERIMENTAL). If unavailable, will fall back based on --extend-fallback."
    )
    var enableExtendExperimental: Bool = false

    @Option(name: .long, help: "Capture display (main or secondary). Ignored if --capture-display-id is set.")
    var captureDisplay: CaptureDisplay = .main

    @Option(name: .long, help: "Explicit CGDirectDisplayID to capture (overrides --capture-display).")
    var captureDisplayID: UInt32?

    @Option(name: .long, help: "When extend mode setup fails: secondary, mirror, or fail.")
    var extendFallback: ExtendFallback = .secondary

    @Flag(name: .long, inversion: .prefixedNo, help: "Capture at native (physical pixel) resolution. Default: true (Retina quality). Use --no-native-resolution for lower-res capture.")
    var nativeResolution: Bool = true

    @Option(name: .long, help: "Log level (debug, info, warn, error)")
    var logLevel: String = "info"

    @Flag(name: .long, help: "Use test pattern instead of real capture")
    var testPattern = false
    
    @Flag(name: .long, help: "Send raw RGBA frames instead of H.264 encoded")
    var raw = false
    
    @Option(name: .long, help: "Target bitrate in Mbps (default: 25)")
    var bitrate: Int = 25

    @Option(name: .long, help: "Duration in seconds (0 = indefinite)")
    var duration: Int = 0

    @Flag(name: .long, help: "Show version and exit")
    var showVersion = false

    mutating func run() async throws {
        // Capture values before closure
        let logLevelValue = logLevel
        let targetIPValue = targetIP
        let portValue = port
        let modeValue = mode
        let enableExtendExperimentalValue = enableExtendExperimental
        let captureDisplayValue = captureDisplay
        let captureDisplayIDValue = captureDisplayID
        let extendFallbackValue = extendFallback
        let nativeResolutionValue = nativeResolution
        let useTestPattern = testPattern
        let useRaw = raw
        let targetBitrate = Int32(bitrate * 1_000_000)
        let runDuration = duration

        // Setup logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = Logger.Level(rawValue: logLevelValue) ?? .info
            return handler
        }

        let logger = Logger(label: "com.thundermirror.sender")

        logger.info("ThunderMirror Mac Sender v0.3.0")
        logger.info("Target: \(targetIPValue):\(portValue)")
        logger.info("Mode: \(modeValue)")
        logger.info("Source: \(useTestPattern ? "test pattern" : "screen capture")")
        logger.info("Encoding: \(useRaw ? "raw RGBA" : "H.264 @ \(bitrate) Mbps")")

        // Extend mode is usable without virtual display creation:
        // by default it will capture a secondary display if present, otherwise fall back per --extend-fallback.
        let attemptVirtualDisplay: Bool = {
            guard modeValue == .extend else { return false }
            guard enableExtendExperimentalValue else { return false }
            #if EXTEND_EXPERIMENTAL
            return true
            #else
            logger.warning("Requested experimental virtual display attempt, but binary was not built with -DEXTEND_EXPERIMENTAL. Will fall back based on --extend-fallback.")
            return false
            #endif
        }()

        // Connect to receiver
        let client = QuicClient()
        
        logger.info("Connecting to \(targetIPValue):\(portValue)...")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.connect(host: targetIPValue, port: portValue) { result in
                switch result {
                case .success:
                    logger.info("Connected!")
                    
                    if useTestPattern {
                        // Phase 1: Test pattern streaming (always raw)
                        streamTestPatternAsync(client: client, logger: logger, duration: runDuration, continuation: continuation)
                    } else {
                        // Phase 2/3: Real screen capture
                        Task {
                            do {
                                try await streamScreenCaptureAsync(
                                    client: client,
                                    logger: logger,
                                    duration: runDuration,
                                    mode: modeValue,
                                    attemptVirtualDisplay: attemptVirtualDisplay,
                                    captureDisplay: captureDisplayValue,
                                    captureDisplayID: captureDisplayIDValue,
                                    extendFallback: extendFallbackValue,
                                    nativeResolution: nativeResolutionValue,
                                    useH264: !useRaw,
                                    bitrate: targetBitrate
                                )
                                continuation.resume()
                            } catch {
                                logger.error("Screen capture failed: \(error.localizedDescription)")
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                    
                case .failure(let error):
                    logger.error("Connection failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
}

/// Streaming mode
enum StreamMode: String, ExpressibleByArgument, CustomStringConvertible {
    case mirror
    case extend

    var description: String {
        rawValue
    }
}

enum CaptureDisplay: String, ExpressibleByArgument, CustomStringConvertible {
    case main
    case secondary

    var description: String { rawValue }
}

enum ExtendFallback: String, ExpressibleByArgument, CustomStringConvertible {
    case secondary
    case mirror
    case fail

    var description: String { rawValue }
}

/// Stream test patterns (Phase 1 fallback) - free function to avoid self capture
func streamTestPatternAsync(
    client: QuicClient,
    logger: Logger,
    duration: Int,
    continuation: CheckedContinuation<Void, Error>
) {
    logger.info("Starting test pattern stream...")
    
    let width: UInt16 = 1920
    let height: UInt16 = 1080
    let frameInterval = 1.0 / 60.0
    
    var sequence: UInt64 = 0
    let startTime = Date()
    var timer: DispatchSourceTimer?
    let timerQueue = DispatchQueue(label: "com.thundermirror.timer")
    var lastStatsTime = Date()
    var framesSinceStats: UInt64 = 0
    var bytesSinceStats: UInt64 = 0
    
    timer = DispatchSource.makeTimerSource(queue: timerQueue)
    timer?.schedule(deadline: .now(), repeating: frameInterval)
    timer?.setEventHandler {
        let timestampUs = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
        
        let pattern = TestPattern.generateColorBars(width: width, height: height)
        let frameData = createFrameData(
            sequence: sequence,
            timestampUs: timestampUs,
            width: width,
            height: height,
            payload: pattern
        )
        
        client.send(frameData) { sendResult in
            switch sendResult {
            case .success:
                framesSinceStats += 1
                bytesSinceStats += UInt64(frameData.count)
                
                // Log stats every second
                let now = Date()
                if now.timeIntervalSince(lastStatsTime) >= 1.0 {
                    let fps = Double(framesSinceStats) / now.timeIntervalSince(lastStatsTime)
                    let mbps = Double(bytesSinceStats * 8) / (now.timeIntervalSince(lastStatsTime) * 1_000_000)
                    logger.info("Stats: \(String(format: "%.1f", fps)) fps, \(String(format: "%.1f", mbps)) Mbps, frame \(sequence)")
                    framesSinceStats = 0
                    bytesSinceStats = 0
                    lastStatsTime = now
                }
            case .failure(let error):
                logger.error("Failed to send frame: \(error.localizedDescription)")
                timer?.cancel()
                continuation.resume(throwing: error)
            }
        }
        
        sequence += 1
    }
    timer?.resume()
    
    // Stop after duration (or run indefinitely if 0)
    let stopTime = duration > 0 ? duration : 10
    DispatchQueue.global().asyncAfter(deadline: .now() + Double(stopTime)) {
        timer?.cancel()
        client.close()
        logger.info("Streaming complete. Sent \(sequence) frames.")
        continuation.resume()
    }
}

/// Stream real screen capture (Phase 2/3) - free function to avoid self capture
@available(macOS 12.3, *)
func streamScreenCaptureAsync(
    client: QuicClient,
    logger: Logger,
    duration: Int,
    mode: StreamMode = .mirror,
    attemptVirtualDisplay: Bool = false,
    captureDisplay: CaptureDisplay = .main,
    captureDisplayID: UInt32? = nil,
    extendFallback: ExtendFallback = .secondary,
    nativeResolution: Bool = true,
    useH264: Bool = true,
    bitrate: Int32 = 10_000_000
) async throws {
    logger.info("Starting screen capture (mode: \(mode), H.264: \(useH264), native: \(nativeResolution))...")
    
    let capture = ScreenCapture()
    capture.captureAtNativeResolution = nativeResolution
    let encoder: H264Encoder? = useH264 ? H264Encoder() : nil
    var virtualDisplayHandle: VirtualDisplayHandle?
    
    var sequence: UInt64 = 0
    let startTime = Date()
    var lastStatsTime = Date()
    var framesSinceStats: UInt64 = 0
    var bytesSinceStats: UInt64 = 0
    var shouldStop = false
    var encoderInitialized = false
    var currentWidth: UInt16 = 0
    var currentHeight: UInt16 = 0
    
    // Handle encoded frames from H.264 encoder
    encoder?.onEncodedFrame = { nalData, isKeyframe in
        guard !shouldStop else { return }
        
        let timestampUs = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
        
        let frameData = createFrameData(
            sequence: sequence,
            timestampUs: timestampUs,
            width: currentWidth,
            height: currentHeight,
            payload: nalData,
            frameType: 1  // H264Frame
        )
        
        client.send(frameData) { sendResult in
            switch sendResult {
            case .success:
                framesSinceStats += 1
                bytesSinceStats += UInt64(frameData.count)
                
                // Log stats every second
                let now = Date()
                if now.timeIntervalSince(lastStatsTime) >= 1.0 {
                    let fps = Double(framesSinceStats) / now.timeIntervalSince(lastStatsTime)
                    let mbps = Double(bytesSinceStats * 8) / (now.timeIntervalSince(lastStatsTime) * 1_000_000)
                    let keyframeMarker = isKeyframe ? " [K]" : ""
                    logger.info("Stats: \(String(format: "%.1f", fps)) fps, \(String(format: "%.1f", mbps)) Mbps, \(currentWidth)x\(currentHeight), H.264, frame \(sequence)\(keyframeMarker)")
                    framesSinceStats = 0
                    bytesSinceStats = 0
                    lastStatsTime = now
                }
            case .failure(let error):
                logger.error("Failed to send frame: \(error.localizedDescription)")
                shouldStop = true
            }
        }
        
        sequence += 1
    }
    
    // Handle frames from capture
    capture.onFrame = { rgbaData, width, height in
        guard !shouldStop else { return }
        
        currentWidth = width
        currentHeight = height
        
        if useH264, let encoder = encoder {
            // Initialize encoder on first frame or resolution change
            if !encoderInitialized || width != UInt16(encoder.width) || height != UInt16(encoder.height) {
                do {
                    try encoder.initialize(width: Int32(width), height: Int32(height), bitrate: bitrate, fps: 60)
                    encoderInitialized = true
                } catch {
                    logger.error("Failed to initialize encoder: \(error.localizedDescription)")
                    shouldStop = true
                    return
                }
            }
            
            // Create pixel buffer from RGBA data
            var pixelBuffer: CVPixelBuffer?
            let attrs: [String: Any] = [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
            
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(width),
                Int(height),
                kCVPixelFormatType_32BGRA,
                attrs as CFDictionary,
                &pixelBuffer
            )
            
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
                logger.error("Failed to create pixel buffer")
                return
            }
            
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
                let dest = baseAddress.assumingMemoryBound(to: UInt8.self)
                
                // Convert RGBA to BGRA
                rgbaData.withUnsafeBytes { srcPtr in
                    guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                    
                    for y in 0..<Int(height) {
                        for x in 0..<Int(width) {
                            let srcOffset = (y * Int(width) + x) * 4
                            let dstOffset = y * bytesPerRow + x * 4
                            
                            // RGBA -> BGRA
                            dest[dstOffset + 0] = src[srcOffset + 2]  // B
                            dest[dstOffset + 1] = src[srcOffset + 1]  // G
                            dest[dstOffset + 2] = src[srcOffset + 0]  // R
                            dest[dstOffset + 3] = src[srcOffset + 3]  // A
                        }
                    }
                }
            }
            
            // Encode frame
            do {
                try encoder.encode(pixelBuffer: buffer)
            } catch {
                logger.error("Encoding failed: \(error.localizedDescription)")
            }
        } else {
            // Raw RGBA streaming (Phase 2 mode)
            let timestampUs = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
            
            let frameData = createFrameData(
                sequence: sequence,
                timestampUs: timestampUs,
                width: width,
                height: height,
                payload: rgbaData,
                frameType: 0  // RawFrame
            )
            
            client.send(frameData) { sendResult in
                switch sendResult {
                case .success:
                    framesSinceStats += 1
                    bytesSinceStats += UInt64(frameData.count)
                    
                    // Log stats every second
                    let now = Date()
                    if now.timeIntervalSince(lastStatsTime) >= 1.0 {
                        let fps = Double(framesSinceStats) / now.timeIntervalSince(lastStatsTime)
                        let mbps = Double(bytesSinceStats * 8) / (now.timeIntervalSince(lastStatsTime) * 1_000_000)
                        logger.info("Stats: \(String(format: "%.1f", fps)) fps, \(String(format: "%.1f", mbps)) Mbps, \(width)x\(height), raw, frame \(sequence)")
                        framesSinceStats = 0
                        bytesSinceStats = 0
                        lastStatsTime = now
                    }
                case .failure(let error):
                    logger.error("Failed to send frame: \(error.localizedDescription)")
                    shouldStop = true
                }
            }
            
            sequence += 1
        }
    }
    
    // Handle resolution changes
    capture.onResolutionChange = { width, height in
        logger.info("Resolution changed to \(width)x\(height)")
        // Encoder will be re-initialized on next frame
    }
    
    // Compute baseline capture selection.
    let baseSelection: ScreenCapture.CaptureDisplaySelection = {
        if let id = captureDisplayID {
            return .displayID(CGDirectDisplayID(id))
        }
        // In extend mode, default to secondary unless user explicitly requested secondary/main.
        if mode == .extend, captureDisplay == .main {
            return .secondary
        }
        return captureDisplay == .secondary ? .secondary : .main
    }()

    // Start capture
    do {
        switch mode {
        case .mirror:
            try await capture.startCapture(selection: baseSelection)
        case .extend:
            if attemptVirtualDisplay {
                do {
                    let manager = VirtualDisplayManager(logger: logger)
                    virtualDisplayHandle = try manager.createVirtualDisplay()
                    if let vdID = virtualDisplayHandle?.displayID {
                        try await capture.startCapture(selection: .displayID(vdID))
                    } else {
                        throw ScreenCaptureError.captureError("Virtual display created without a displayID")
                    }
                } catch {
                    logger.warning("Virtual display setup failed (\(error.localizedDescription)).")
                    virtualDisplayHandle?.teardown()
                    virtualDisplayHandle = nil
                    // Fall through to extend fallback selection
                    switch extendFallback {
                    case .secondary:
                        logger.info("Extend fallback: capturing secondary display (if present).")
                        try await capture.startCapture(selection: .secondary)
                    case .mirror:
                        logger.info("Extend fallback: capturing main display (mirror).")
                        try await capture.startCapture(selection: .main)
                    case .fail:
                        logger.error("Extend fallback: fail (aborting).")
                        throw error
                    }
                }
            } else {
                // No virtual display attempt: use extend baseline selection (defaults to secondary).
                switch extendFallback {
                case .secondary:
                    try await capture.startCapture(selection: baseSelection)
                case .mirror:
                    try await capture.startCapture(selection: .main)
                case .fail:
                    // If user asked to fail rather than degrade, do so when we can't attempt/create virtual display.
                    throw ScreenCaptureError.captureError("Extend mode requested with --extend-fallback=fail, but no virtual display attempt is enabled/available.")
                }
            }
        }
    } catch {
        virtualDisplayHandle?.teardown()
        virtualDisplayHandle = nil
        throw error
    }
    
    // Wait for duration or signal
    if duration > 0 {
        try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000)
    } else {
        // Run indefinitely - wait for interrupt signal
        logger.info("Streaming... Press Ctrl+C to stop")
        
        // Setup signal handler for graceful shutdown
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        
        await withCheckedContinuation { (signalContinuation: CheckedContinuation<Void, Never>) in
            signalSource.setEventHandler {
                shouldStop = true
                signalSource.cancel()
                signalContinuation.resume()
            }
            signalSource.resume()
        }
    }
    
    // Cleanup
    shouldStop = true
    encoder?.shutdown()
    await capture.stopCapture()
    client.close()
    virtualDisplayHandle?.teardown()
    logger.info("Streaming complete. Sent \(sequence) frames.")
}

/// Frame types matching the protocol
enum FrameType: UInt8 {
    case raw = 0      // Raw RGBA pixel data
    case h264 = 1     // H.264 encoded frame
    case control = 2  // Control message
    case stats = 3    // Statistics/heartbeat
}

/// Create frame data with header
/// Protocol: version(1) + frame_type(1) + sequence(8) + timestamp_us(8) + width(2) + height(2) + payload_size(4) = 26 bytes header
func createFrameData(sequence: UInt64, timestampUs: UInt64, width: UInt16, height: UInt16, payload: Data, frameType: UInt8 = 0) -> Data {
    var frameData = Data(capacity: 26 + payload.count)
    frameData.append(1) // version
    frameData.append(frameType) // frame_type
    frameData.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: timestampUs.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) })
    frameData.append(payload)
    return frameData
}
