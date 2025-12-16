import ArgumentParser
import Foundation
import Logging

/// ThunderMirror Mac Sender CLI
///
/// Captures the Mac screen and streams it to a Windows receiver over Thunderbolt.
@main
struct ThunderMirror: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ThunderMirror",
        abstract: "Stream Mac display to Windows over Thunderbolt",
        version: "0.1.0"
    )

    @Option(name: .shortAndLong, help: "Windows receiver IP address")
    var targetIP: String = "192.168.50.2"

    @Option(name: .shortAndLong, help: "Streaming port")
    var port: UInt16 = 9999

    @Option(name: .long, help: "Streaming mode (mirror or extend)")
    var mode: StreamMode = .mirror

    @Option(name: .long, help: "Log level (debug, info, warn, error)")
    var logLevel: String = "info"

    @Flag(name: .long, help: "Show version and exit")
    var showVersion = false

    mutating func run() async throws {
        // Capture values before closure
        let logLevelValue = logLevel
        let targetIPValue = targetIP
        let portValue = port
        let modeValue = mode

        // Setup logging
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = Logger.Level(rawValue: logLevelValue) ?? .info
            return handler
        }

        let logger = Logger(label: "com.thundermirror.sender")

        logger.info("ThunderMirror Mac Sender v0.1.0")
        logger.info("Target: \(targetIPValue):\(portValue)")
        logger.info("Mode: \(modeValue)")

        // Phase 1: QUIC connection and test pattern streaming
        let client = QuicClient()
        
        logger.info("Connecting to \(targetIPValue):\(portValue)...")
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.connect(host: targetIPValue, port: portValue) { result in
                switch result {
                case .success:
                    logger.info("Connected! Starting test pattern stream...")
                    
                    // Stream test patterns at 60 fps
                    let width: UInt16 = 1920
                    let height: UInt16 = 1080
                    let fps: UInt8 = 60
                    let frameInterval = 1.0 / Double(fps)
                    
                    var sequence: UInt64 = 0
                    let startTime = Date()
                    var timer: DispatchSourceTimer?
                    let timerQueue = DispatchQueue(label: "com.thundermirror.timer")
                    
                    // Create a dispatch timer to send frames
                    timer = DispatchSource.makeTimerSource(queue: timerQueue)
                    timer?.schedule(deadline: .now(), repeating: frameInterval)
                    timer?.setEventHandler {
                        let timestampUs = UInt64(Date().timeIntervalSince(startTime) * 1_000_000)
                        
                        // Generate test pattern
                        let pattern = TestPattern.generateColorBars(width: width, height: height)
                        
                        // Create frame header (26 bytes)
                        // Protocol: version(1) + frame_type(1) + sequence(8) + timestamp_us(8) + width(2) + height(2) + payload_size(4)
                        var frameData = Data(capacity: 26 + pattern.count)
                        frameData.append(1) // version
                        frameData.append(0) // frame_type: RawFrame
                        frameData.append(contentsOf: withUnsafeBytes(of: sequence.bigEndian) { Data($0) })
                        frameData.append(contentsOf: withUnsafeBytes(of: timestampUs.bigEndian) { Data($0) })
                        frameData.append(contentsOf: withUnsafeBytes(of: width.bigEndian) { Data($0) })
                        frameData.append(contentsOf: withUnsafeBytes(of: height.bigEndian) { Data($0) })
                        frameData.append(contentsOf: withUnsafeBytes(of: UInt32(pattern.count).bigEndian) { Data($0) })
                        frameData.append(pattern)
                        
                        // Send frame
                        client.send(frameData) { sendResult in
                            switch sendResult {
                            case .success:
                                if sequence % 60 == 0 {
                                    logger.info("Sent frame \(sequence)")
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
                    
                    // Run for 10 seconds in Phase 1 (for testing)
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                        timer?.cancel()
                        client.close()
                        logger.info("Streaming complete. Sent \(sequence) frames.")
                        continuation.resume()
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
