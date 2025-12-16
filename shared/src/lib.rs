//! ThunderMirror Shared Library
//!
//! This crate provides shared functionality for the ThunderMirror project:
//! - Transport layer (QUIC/UDP) - Phase 1+
//! - Streaming protocol definitions
//! - Statistics and metrics
//! - Logging utilities

pub mod config;
pub mod error;
pub mod logging;
pub mod protocol;
pub mod stats;
pub mod test_pattern;
pub mod transport;

pub use config::Config;
pub use error::{Error, Result};

/// Library version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Default Mac IP for Thunderbolt Bridge
pub const DEFAULT_MAC_IP: &str = "192.168.50.1";

/// Default Windows IP for Thunderbolt Bridge  
pub const DEFAULT_WIN_IP: &str = "192.168.50.2";

/// Default streaming port
pub const DEFAULT_PORT: u16 = 9999;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_format() {
        // VERSION is set at compile time from Cargo.toml, verify it's semver-like
        assert!(VERSION.contains('.'), "Version should contain a dot");
    }

    #[test]
    fn test_defaults() {
        assert_eq!(DEFAULT_MAC_IP, "192.168.50.1");
        assert_eq!(DEFAULT_WIN_IP, "192.168.50.2");
        assert_eq!(DEFAULT_PORT, 9999);
    }
}
