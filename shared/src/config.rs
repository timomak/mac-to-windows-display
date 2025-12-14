//! Configuration management

use serde::{Deserialize, Serialize};

use crate::{DEFAULT_MAC_IP, DEFAULT_PORT, DEFAULT_WIN_IP};

/// Application configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// IP address to bind/connect (depends on role)
    pub bind_address: String,

    /// Target IP address for connection
    pub target_address: String,

    /// Port for streaming
    pub port: u16,

    /// Streaming mode
    pub mode: StreamMode,

    /// Log level
    pub log_level: String,

    /// Log directory
    pub log_dir: String,
}

/// Streaming mode
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StreamMode {
    /// Mirror the primary display
    Mirror,

    /// Extend with virtual display (experimental)
    Extend,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            bind_address: "0.0.0.0".to_string(),
            target_address: DEFAULT_WIN_IP.to_string(),
            port: DEFAULT_PORT,
            mode: StreamMode::Mirror,
            log_level: "info".to_string(),
            log_dir: "logs".to_string(),
        }
    }
}

impl Config {
    /// Create config for Mac sender
    pub fn mac_sender() -> Self {
        Self {
            bind_address: DEFAULT_MAC_IP.to_string(),
            target_address: DEFAULT_WIN_IP.to_string(),
            ..Default::default()
        }
    }

    /// Create config for Windows receiver
    pub fn win_receiver() -> Self {
        Self {
            bind_address: DEFAULT_WIN_IP.to_string(),
            target_address: DEFAULT_MAC_IP.to_string(),
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.port, 9999);
        assert_eq!(config.mode, StreamMode::Mirror);
    }

    #[test]
    fn test_mac_sender_config() {
        let config = Config::mac_sender();
        assert_eq!(config.bind_address, "192.168.50.1");
        assert_eq!(config.target_address, "192.168.50.2");
    }
}
