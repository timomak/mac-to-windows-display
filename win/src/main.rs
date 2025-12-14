//! ThunderMirror Windows Receiver
//!
//! Receives screen stream from Mac and displays it.

use clap::Parser;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

/// ThunderMirror Windows Receiver
///
/// Receives and displays screen stream from Mac over Thunderbolt.
#[derive(Parser, Debug)]
#[command(name = "thunder_receiver")]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Mac sender IP address
    #[arg(short = 't', long, default_value = "192.168.50.1")]
    mac_ip: String,

    /// Listening port
    #[arg(short, long, default_value_t = 9999)]
    port: u16,

    /// Run in fullscreen mode
    #[arg(short, long)]
    fullscreen: bool,

    /// Log level (trace, debug, info, warn, error)
    #[arg(long, default_value = "info")]
    log_level: String,
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // Initialize logging
    let level = match args.log_level.as_str() {
        "trace" => Level::TRACE,
        "debug" => Level::DEBUG,
        "info" => Level::INFO,
        "warn" => Level::WARN,
        "error" => Level::ERROR,
        _ => Level::INFO,
    };

    let subscriber = FmtSubscriber::builder().with_max_level(level).finish();

    tracing::subscriber::set_global_default(subscriber)?;

    info!("ThunderMirror Windows Receiver v0.1.0");
    info!("Mac IP: {}", args.mac_ip);
    info!("Port: {}", args.port);
    info!("Fullscreen: {}", args.fullscreen);

    // Phase 0: Just print status
    println!(
        r#"
========================================
ThunderMirror - Windows Receiver
========================================

Mac IP:     {}
Port:       {}
Fullscreen: {}

Status: SCAFFOLD (Phase 0)

This is a placeholder. Full implementation coming in Phase 1+.

To test the link:
  .\scripts\check_link_win.ps1

========================================
"#,
        args.mac_ip, args.port, args.fullscreen
    );

    // TODO Phase 1: Implement QUIC listener
    // TODO Phase 2: Implement frame rendering
    // TODO Phase 3: Implement Media Foundation decoding

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_args_defaults() {
        let args = Args::parse_from(["thunder_receiver"]);
        assert_eq!(args.mac_ip, "192.168.50.1");
        assert_eq!(args.port, 9999);
        assert!(!args.fullscreen);
    }
}
