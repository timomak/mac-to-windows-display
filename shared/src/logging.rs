//! Logging utilities

use std::fs;
use std::path::Path;

use chrono::Local;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

/// Initialize logging with file and console output
///
/// # Arguments
/// * `log_dir` - Directory to store log files
/// * `prefix` - Prefix for log file names (e.g., "mac_sender", "win_receiver")
/// * `level` - Log level (debug, info, warn, error)
pub fn init_logging(log_dir: &str, prefix: &str, level: &str) -> crate::Result<()> {
    // Ensure log directory exists
    let log_path = Path::new(log_dir);
    if !log_path.exists() {
        fs::create_dir_all(log_path)?;
    }

    // Create timestamped log file name
    let timestamp = Local::now().format("%Y%m%d_%H%M%S");
    let log_file = log_path.join(format!("{}_{}.log", prefix, timestamp));

    // Create file appender
    let file = fs::File::create(&log_file)?;

    // Build subscriber with both console and file output
    let subscriber = tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(level)))
        .with(
            fmt::layer()
                .with_target(true)
                .with_thread_ids(false)
                .with_file(false),
        )
        .with(
            fmt::layer()
                .with_writer(file)
                .with_ansi(false)
                .with_target(true)
                .with_thread_ids(true),
        );

    tracing::subscriber::set_global_default(subscriber)
        .map_err(|e| crate::Error::Other(format!("Failed to set subscriber: {}", e)))?;

    tracing::info!("Logging initialized - file: {:?}", log_file);

    Ok(())
}

/// Initialize simple console-only logging (for quick testing)
pub fn init_console_logging(level: &str) {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new(level));

    tracing_subscriber::fmt().with_env_filter(filter).init();
}

#[cfg(test)]
mod tests {
    // Logging tests are tricky due to global state
    // Manual testing recommended
}
