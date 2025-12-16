//! Test pattern generator for streaming tests
//!
//! Generates color bar test patterns for validating the streaming pipeline.

use bytes::Bytes;

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
/// # Arguments
/// * `width` - Frame width in pixels
/// * `height` - Frame height in pixels
///
/// # Returns
/// RGBA pixel data as bytes (4 bytes per pixel: R, G, B, A)
pub fn generate_color_bars(width: u16, height: u16) -> Bytes {
    let width = width as usize;
    let height = height as usize;
    let pixel_count = width * height;
    let mut buffer = Vec::with_capacity(pixel_count * 4);

    // Define 8 color bars (RGBA format)
    let bars = [
        (255, 255, 255, 255), // White
        (255, 255, 0, 255),   // Yellow
        (0, 255, 255, 255),   // Cyan
        (0, 255, 0, 255),     // Green
        (255, 0, 255, 255),   // Magenta
        (255, 0, 0, 255),     // Red
        (0, 0, 255, 255),     // Blue
        (0, 0, 0, 255),       // Black
    ];

    let bar_width = width / 8;

    for _y in 0..height {
        for x in 0..width {
            let bar_index = (x / bar_width).min(7);
            let (r, g, b, a) = bars[bar_index];
            buffer.push(r);
            buffer.push(g);
            buffer.push(b);
            buffer.push(a);
        }
    }

    Bytes::from(buffer)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_color_bars_generation() {
        let width: u16 = 1920;
        let height: u16 = 1080;
        let pattern = generate_color_bars(width, height);

        let width = width as usize;
        let height = height as usize;

        // Verify size: width * height * 4 bytes per pixel
        assert_eq!(pattern.len(), width * height * 4);

        // Verify first pixel is white (first bar)
        assert_eq!(pattern[0], 255); // R
        assert_eq!(pattern[1], 255); // G
        assert_eq!(pattern[2], 255); // B
        assert_eq!(pattern[3], 255); // A

        // Verify a pixel in the middle of the first bar is white
        let mid_bar_pixel = (width / 16) * 4; // Middle of first bar
        assert_eq!(pattern[mid_bar_pixel], 255);
        assert_eq!(pattern[mid_bar_pixel + 1], 255);
        assert_eq!(pattern[mid_bar_pixel + 2], 255);
        assert_eq!(pattern[mid_bar_pixel + 3], 255);

        // Verify a pixel in the red bar (6th bar, index 5)
        let red_bar_start = (width / 8 * 5) * 4;
        assert_eq!(pattern[red_bar_start], 255); // R
        assert_eq!(pattern[red_bar_start + 1], 0); // G
        assert_eq!(pattern[red_bar_start + 2], 0); // B
        assert_eq!(pattern[red_bar_start + 3], 255); // A
    }

    #[test]
    fn test_color_bars_different_sizes() {
        // Test small size
        let small = generate_color_bars(640, 480);
        assert_eq!(small.len(), 640 * 480 * 4);

        // Test large size
        let large = generate_color_bars(3840, 2160);
        assert_eq!(large.len(), 3840 * 2160 * 4);
    }
}
