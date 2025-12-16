//! ThunderMirror Windows Receiver
//!
//! Receives screen stream from Mac and displays it.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use bytes::{Buf, Bytes};
use clap::Parser;
use minifb::{Key, Window, WindowOptions};
use openh264::decoder::Decoder;
use openh264::formats::YUVSource;
use quinn::{Endpoint, ServerConfig};
use rustls::{Certificate, PrivateKey};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn, Level};
use tracing_subscriber::FmtSubscriber;

/// Frame header size in bytes
const FRAME_HEADER_SIZE: usize = 26;

/// Frame types from protocol
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
enum FrameType {
    Raw = 0,
    H264 = 1,
    Control = 2,
    Stats = 3,
}

impl TryFrom<u8> for FrameType {
    type Error = anyhow::Error;

    fn try_from(value: u8) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(FrameType::Raw),
            1 => Ok(FrameType::H264),
            2 => Ok(FrameType::Control),
            3 => Ok(FrameType::Stats),
            _ => Err(anyhow::anyhow!("Unknown frame type: {}", value)),
        }
    }
}

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

/// Frame data received from sender
struct FrameData {
    width: u16,
    height: u16,
    rgba_data: Vec<u8>,
    #[allow(dead_code)]
    sequence: u64,
    frame_type: FrameType,
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

    info!("ThunderMirror Windows Receiver v0.2.0");
    info!("Listening on port: {}", args.port);
    info!("Fullscreen: {}", args.fullscreen);

    // Create tokio runtime
    let rt = tokio::runtime::Runtime::new()?;

    // Run QUIC server in background and receive frames
    let (tx, mut rx) = mpsc::channel::<FrameData>(10);

    let port = args.port;
    rt.spawn(async move {
        if let Err(e) = run_quic_server(port, tx).await {
            error!("QUIC server error: {}", e);
        }
    });

    // Initialize H.264 decoder
    let mut h264_decoder = Decoder::new().expect("Failed to create H.264 decoder");
    info!("H.264 decoder initialized (OpenH264)");

    // Initialize window with default size (will resize when we receive frames)
    let mut width: usize = 1920;
    let mut height: usize = 1080;
    let mut buffer: Vec<u32> = vec![0; width * height];

    let window_opts = if args.fullscreen {
        WindowOptions {
            resize: true,
            borderless: true,
            ..Default::default()
        }
    } else {
        WindowOptions {
            resize: true,
            ..Default::default()
        }
    };

    let mut window = Window::new(
        "ThunderMirror - Waiting for stream...",
        width,
        height,
        window_opts,
    )?;

    // Limit to ~60 fps for display
    window.set_target_fps(60);

    let mut last_stats = Instant::now();
    let mut frame_count = 0u64;
    let mut total_bytes = 0u64;
    let mut h264_frames = 0u64;
    let mut raw_frames = 0u64;

    info!("Window created, waiting for frames...");

    while window.is_open() && !window.is_key_down(Key::Escape) {
        // Check for new frames (non-blocking)
        while let Ok(frame) = rx.try_recv() {
            let new_width = frame.width as usize;
            let new_height = frame.height as usize;

            // Resize buffer if needed
            if new_width != width || new_height != height {
                width = new_width;
                height = new_height;
                buffer = vec![0; width * height];
                info!("Resolution changed to {}x{}", width, height);
            }

            match frame.frame_type {
                FrameType::H264 => {
                    // Decode H.264 frame
                    match h264_decoder.decode(&frame.rgba_data) {
                        Ok(Some(decoded)) => {
                            // Get dimensions from decoded frame
                            let (dec_width, dec_height) = decoded.dimensions();
                            
                            // Convert YUV to RGB and store in buffer
                            // First, create an RGB buffer
                            let mut rgb_buffer = vec![0u8; dec_width * dec_height * 3];
                            decoded.write_rgb8(&mut rgb_buffer);
                            
                            // Convert RGB to u32 buffer (0xRRGGBB format for minifb)
                            for (i, pixel) in rgb_buffer.chunks(3).enumerate() {
                                if i < buffer.len() && pixel.len() >= 3 {
                                    let r = pixel[0] as u32;
                                    let g = pixel[1] as u32;
                                    let b = pixel[2] as u32;
                                    buffer[i] = (r << 16) | (g << 8) | b;
                                }
                            }
                            h264_frames += 1;
                        }
                        Ok(None) => {
                            // Decoder needs more data (buffering)
                            debug!("H.264 decoder buffering...");
                        }
                        Err(e) => {
                            warn!("H.264 decode error: {:?}", e);
                        }
                    }
                }
                FrameType::Raw => {
                    // Raw RGBA data - convert directly
                    for (i, pixel) in frame.rgba_data.chunks(4).enumerate() {
                        if i < buffer.len() && pixel.len() >= 3 {
                            let r = pixel[0] as u32;
                            let g = pixel[1] as u32;
                            let b = pixel[2] as u32;
                            buffer[i] = (r << 16) | (g << 8) | b;
                        }
                    }
                    raw_frames += 1;
                }
                _ => {
                    debug!("Ignoring frame type: {:?}", frame.frame_type);
                }
            }

            frame_count += 1;
            total_bytes += frame.rgba_data.len() as u64;
        }

        // Update window
        window.update_with_buffer(&buffer, width, height)?;

        // Log stats every second
        if last_stats.elapsed() >= Duration::from_secs(1) {
            let fps = frame_count as f64 / last_stats.elapsed().as_secs_f64();
            let mbps =
                (total_bytes as f64 * 8.0) / (last_stats.elapsed().as_secs_f64() * 1_000_000.0);
            let codec = if h264_frames > raw_frames { "H.264" } else { "raw" };
            info!(
                "Stats: {:.1} FPS, {:.1} Mbps, {} (h264:{}, raw:{})",
                fps, mbps, codec, h264_frames, raw_frames
            );

            window.set_title(&format!(
                "ThunderMirror - {}x{} @ {:.0} FPS, {:.0} Mbps [{}]",
                width, height, fps, mbps, codec
            ));

            frame_count = 0;
            total_bytes = 0;
            h264_frames = 0;
            raw_frames = 0;
            last_stats = Instant::now();
        }
    }

    info!("Window closed, shutting down...");
    Ok(())
}


async fn run_quic_server(port: u16, tx: mpsc::Sender<FrameData>) -> anyhow::Result<()> {
    let addr: SocketAddr = format!("0.0.0.0:{}", port).parse()?;
    let server_config = create_server_config()?;
    let endpoint = Endpoint::server(server_config, addr)?;

    info!("QUIC server listening on {}", addr);

    loop {
        let incoming = endpoint.accept().await;
        if let Some(connecting) = incoming {
            let tx = tx.clone();
            tokio::spawn(async move {
                match connecting.await {
                    Ok(conn) => {
                        info!("Connection accepted from {}", conn.remote_address());
                        if let Err(e) = handle_connection(conn, tx).await {
                            error!("Connection error: {}", e);
                        }
                    }
                    Err(e) => {
                        error!("Connection failed: {}", e);
                    }
                }
            });
        }
    }
}

async fn handle_connection(
    conn: quinn::Connection,
    tx: mpsc::Sender<FrameData>,
) -> anyhow::Result<()> {
    // Accept unidirectional streams
    loop {
        match conn.accept_uni().await {
            Ok(mut recv) => {
                // Read all data from stream
                let data = recv.read_to_end(16 * 1024 * 1024).await?;

                if data.len() < FRAME_HEADER_SIZE {
                    warn!("Received data too small for header");
                    continue;
                }

                // Parse frame header (big-endian)
                let mut bytes = Bytes::from(data);
                let _version = bytes.get_u8();
                let frame_type_raw = bytes.get_u8();
                let sequence = bytes.get_u64();
                let _timestamp_us = bytes.get_u64();
                let width = bytes.get_u16();
                let height = bytes.get_u16();
                let payload_size = bytes.get_u32() as usize;

                // Parse frame type
                let frame_type = match FrameType::try_from(frame_type_raw) {
                    Ok(ft) => ft,
                    Err(e) => {
                        warn!("Invalid frame type: {}", e);
                        continue;
                    }
                };

                if bytes.remaining() < payload_size {
                    warn!(
                        "Payload size mismatch: expected {}, got {}",
                        payload_size,
                        bytes.remaining()
                    );
                    continue;
                }

                let rgba_data = bytes.slice(..payload_size).to_vec();

                debug!(
                    "Received frame: seq={}, type={:?}, {}x{}, {} bytes",
                    sequence,
                    frame_type,
                    width,
                    height,
                    payload_size
                );

                // Send to renderer
                if tx
                    .send(FrameData {
                        width,
                        height,
                        rgba_data,
                        sequence,
                        frame_type,
                    })
                    .await
                    .is_err()
                {
                    warn!("Frame channel closed");
                    break;
                }
            }
            Err(e) => {
                // Connection closed
                info!("Connection closed: {}", e);
                break;
            }
        }
    }

    Ok(())
}

fn create_server_config() -> anyhow::Result<ServerConfig> {
    // Generate a self-signed certificate for testing
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])?;
    let cert_der = cert.serialize_der()?;
    let key_der = cert.serialize_private_key_der();

    let cert = Certificate(cert_der);
    let key = PrivateKey(key_der);

    let mut rustls_config = rustls::ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)?;

    // Configure for low latency
    rustls_config.max_early_data_size = u32::MAX;
    rustls_config.alpn_protocols = vec![b"thunder-mirror".to_vec()];

    let mut server_config = ServerConfig::with_crypto(Arc::new(rustls_config));
    server_config.transport = Arc::new(quinn::TransportConfig::default());

    Ok(server_config)
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
