import ArgumentParser
import Foundation
import Logging
import ScreenCaptureKit

/// ThunderMirror Mac Sender CLI
///
/// Captures the Mac screen and streams it to a Windows receiver over Thunderbolt.
@main
struct ThunderMirror: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ThunderMirror",
        abstract: "Stream Mac display to Windows over Thunderbolt",
        version: "0.2.0"
    )

    @Option(name: .shortAndLong, help: "Windows receiver IP address")
    var targetIP: String = "192.168.50.2"

    @Option(name: .shortAndLong, help: "Streaming port")
    var port: UInt16 = 9999

    @Option(name: .long, help: "Streaming mode (mirror or extend)")
    var mode: StreamMode = .mirror

    @Option(name: .long, help: "Log level (debug, info, warn, error)")
    var logLevel: String = "info"

    @Flag(name: .long, help: "Use test pattern instead of real capture")
    var testPattern = false

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
        let useTestPattern = testPattern
        let runDuration = duration

        // Setup logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = Logger.Level(rawValue: logLevelValue) ?? .info
            return handler
        }

        let logger = Logger(label: "com.thundermirror.sender")

        logger.info("ThunderMirror Mac Sender v0.2.0")
        logger.info("Target: \(targetIPValue):\(portValue)")
        logger.info("Mode: \(modeValue)")
        logger.info("Source: \(useTestPattern ? "test pattern" : "screen capture")")

        // Connect to receiver
        let client = QuicClient()
        
        logger.info("Connecting to \(targetIPValue):\(portValue)...")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.connect(host: targetIPValue, port: portValue) { result in
                switch result {
                case .success:
                    logger.info("Connected!")
                    
                    if useTestPattern {
                        // Phase 1: Test pattern streaming
                        streamTestPatternAsync(client: client, logger: logger, duration: runDuration, continuation: continuation)
                    } else {
                        // Phase 2: Real screen capture
                        Task {
                            do {
                                try await streamScreenCaptureAsync(client: client, logger: logger, duration: runDuration)
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

/// Stream real screen capture (Phase 2) - free function to avoid self capture
@available(macOS 12.3, *)
func streamScreenCaptureAsync(
    client: QuicClient,
    logger: Logger,
    duration: Int
) async throws {
    logger.info("Starting screen capture...")
    
    let capture = ScreenCapture()
    
    var sequence: UInt64 = 0
    let startTime = Date()
    var lastStatsTime = Date()
    var framesSinceStats: UInt64 = 0
    var bytesSinceStats: UInt64 = 0
    var shouldStop = false
    
    // Handle frames from capture
    capture.onFrame = { rgbaData, width, height in
        guard !shouldStop else { return }
        
        let timestampUs = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
        
        let frameData = createFrameData(
            sequence: sequence,
            timestampUs: timestampUs,
            width: width,
            height: height,
            payload: rgbaData
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
                    logger.info("Stats: \(String(format: "%.1f", fps)) fps, \(String(format: "%.1f", mbps)) Mbps, \(width)x\(height), frame \(sequence)")
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
    
    // Handle resolution changes
    capture.onResolutionChange = { width, height in
        logger.info("Resolution changed to \(width)x\(height)")
    }
    
    // Start capture
    try await capture.startCapture()
    
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
    await capture.stopCapture()
    client.close()
    logger.info("Streaming complete. Sent \(sequence) frames.")
}

/// Create frame data with header
/// Protocol: version(1) + frame_type(1) + sequence(8) + timestamp_us(8) + width(2) + height(2) + payload_size(4) = 26 bytes header
func createFrameData(sequence: UInt64, timestampUs: UInt64, width: UInt16, height: UInt16, payload: Data) -> Data {
    var frameData = Data(capacity: 26 + payload.count)
    frameData.append(1) // version
    frameData.append(0) // frame_type: RawFrame
    frameData.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: timestampUs.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Data($0) })
    frameData.append(contentsOf: withUnsafeBytes(of: UInt32(payload.count).bigEndian) { Data($0) })
    frameData.append(payload)
    return frameData
}
