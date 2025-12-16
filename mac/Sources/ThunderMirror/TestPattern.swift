import Foundation

/// Test pattern generator for streaming tests
///
/// Generates color bar test patterns for validating the streaming pipeline.
enum TestPattern {
    /// Generate a color bar test pattern
    ///
    /// Creates a standard SMPTE color bar pattern with 8 vertical bars:
    /// - White (100% white)
    /// - Yellow (R+G)
    /// - Cyan (G+B)
    /// - Green
    /// - Magenta (R+B)
    /// - Red
    /// - Blue
    /// - Black
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels
    ///   - height: Frame height in pixels
    /// - Returns: RGBA pixel data (4 bytes per pixel: R, G, B, A)
    static func generateColorBars(width: UInt16, height: UInt16) -> Data {
        let widthInt = Int(width)
        let heightInt = Int(height)
        let pixelCount = widthInt * heightInt
        var buffer = Data(capacity: pixelCount * 4)
        
        // Define 8 color bars (RGBA format)
        let bars: [(UInt8, UInt8, UInt8, UInt8)] = [
            (255, 255, 255, 255), // White
            (255, 255, 0, 255),   // Yellow
            (0, 255, 255, 255),   // Cyan
            (0, 255, 0, 255),     // Green
            (255, 0, 255, 255),   // Magenta
            (255, 0, 0, 255),     // Red
            (0, 0, 255, 255),     // Blue
            (0, 0, 0, 255),       // Black
        ]
        
        let barWidth = widthInt / 8
        
        for _ in 0..<heightInt {
            for x in 0..<widthInt {
                let barIndex = min(x / barWidth, 7)
                let (r, g, b, a) = bars[barIndex]
                buffer.append(r)
                buffer.append(g)
                buffer.append(b)
                buffer.append(a)
            }
        }
        
        return buffer
    }
}

