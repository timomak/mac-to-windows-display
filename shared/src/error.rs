//! Error types for ThunderMirror

use thiserror::Error;

/// Result type alias using our Error
pub type Result<T> = std::result::Result<T, Error>;

/// ThunderMirror error types
#[derive(Error, Debug)]
pub enum Error {
    /// Network/transport errors
    #[error("Transport error: {0}")]
    Transport(String),

    /// Protocol errors
    #[error("Protocol error: {0}")]
    Protocol(String),

    /// Configuration errors
    #[error("Configuration error: {0}")]
    Config(String),

    /// Capture errors (Mac side)
    #[error("Capture error: {0}")]
    Capture(String),

    /// Encoding errors
    #[error("Encoding error: {0}")]
    Encode(String),

    /// Decoding errors
    #[error("Decoding error: {0}")]
    Decode(String),

    /// Rendering errors (Windows side)
    #[error("Render error: {0}")]
    Render(String),

    /// IO errors
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    /// Generic errors
    #[error("{0}")]
    Other(String),
}

impl Error {
    /// Create a transport error
    pub fn transport(msg: impl Into<String>) -> Self {
        Self::Transport(msg.into())
    }

    /// Create a protocol error
    pub fn protocol(msg: impl Into<String>) -> Self {
        Self::Protocol(msg.into())
    }

    /// Create a config error
    pub fn config(msg: impl Into<String>) -> Self {
        Self::Config(msg.into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let err = Error::transport("connection failed");
        assert_eq!(err.to_string(), "Transport error: connection failed");
    }
}
