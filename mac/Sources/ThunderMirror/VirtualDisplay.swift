import Foundation
import CoreGraphics
import Logging

/// Handle for a created virtual display (experimental).
struct VirtualDisplayHandle {
    let displayID: CGDirectDisplayID
    let teardown: () -> Void
}

enum VirtualDisplayError: LocalizedError {
    case featureNotEnabled
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .featureNotEnabled:
            return "Virtual display creation is disabled (build with -DEXTEND_EXPERIMENTAL)."
        case .notImplemented(let message):
            return message
        }
    }
}

/// Best-effort virtual display creator.
///
/// Note: On macOS 15, CoreGraphics exports Objective-C classes like `CGVirtualDisplay`,
/// but Apple does not ship public headers for them in the macOS SDK, so we intentionally
/// do not call private SPI from this project (yet). See `docs/EXTEND_MODE.md`.
final class VirtualDisplayManager {
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func createVirtualDisplay() throws -> VirtualDisplayHandle {
        #if EXTEND_EXPERIMENTAL
        logger.info("Attempting virtual display creation (EXTEND_EXPERIMENTAL enabled)...")
        throw VirtualDisplayError.notImplemented(
            "macOS does not provide a supported public API for creating a virtual display in this project configuration. " +
            "Implementing true Extend Mode likely requires a DriverKit-based virtual display driver (system extension) " +
            "or using private/undocumented CoreGraphics SPI. See docs/EXTEND_MODE.md."
        )
        #else
        throw VirtualDisplayError.featureNotEnabled
        #endif
    }
}


