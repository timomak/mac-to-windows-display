import ArgumentParser
import Foundation
import Logging

/// ThunderMirror Mac Sender CLI
///
/// Captures the Mac screen and streams it to a Windows receiver over Thunderbolt.
@main
struct ThunderMirror: ParsableCommand {
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

    mutating func run() throws {
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

        // Phase 0: Just print status
        // Phase 1+: Actual streaming implementation

        print("""

        ========================================
        ThunderMirror - Mac Sender
        ========================================

        Target IP: \(targetIPValue)
        Port:      \(portValue)
        Mode:      \(modeValue)

        Status: SCAFFOLD (Phase 0)

        This is a placeholder. Full implementation coming in Phase 1+.

        To test the link:
          ./scripts/check_link_mac.sh

        ========================================
        """)

        // TODO Phase 1: Implement QUIC connection
        // TODO Phase 2: Implement ScreenCaptureKit capture
        // TODO Phase 3: Implement VideoToolbox encoding
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
