//! ThunderMirror Windows Receiver
//!
//! Receives screen stream from Mac and displays it.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use bytes::{Buf, Bytes};
use clap::Parser;
use minifb::{Key, Window, WindowOptions};

#[cfg(windows)]
use windows::Win32::Foundation::HWND;
#[cfg(windows)]
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTOPRIMARY};
#[cfg(windows)]
use windows::Win32::UI::WindowsAndMessaging::{
    FindWindowW, GetWindowLongW, SetWindowLongW, SetWindowPos, 
    GWL_STYLE, HWND_TOPMOST, SWP_FRAMECHANGED, SWP_SHOWWINDOW,
    WS_BORDER, WS_CAPTION, WS_DLGFRAME, WS_MAXIMIZEBOX, WS_MINIMIZEBOX,
    WS_SYSMENU, WS_THICKFRAME,
};
use openh264::decoder::Decoder;
use openh264::formats::YUVSource;

/// Fast YUV to RGB conversion using integer math (BT.709 LIMITED range)
/// VideoToolbox outputs limited range: Y=[16,235], UV=[16,240]
/// This function expands to full RGB [0,255]
#[inline(always)]
fn yuv_to_rgb_bt709_limited(y: u8, u: u8, v: u8) -> (u8, u8, u8) {
    // BT.709 limited range to full range RGB conversion
    // First expand Y from [16,235] to [0,255]: Y' = (Y - 16) * 255 / 219
    // Expand UV from [16,240] centered at 128 to [-128,127]: UV' = (UV - 128) * 255 / 224
    //
    // Then apply BT.709 matrix:
    // R = Y' + 1.5748 * V'
    // G = Y' - 0.1873 * U' - 0.4681 * V'  
    // B = Y' + 1.8556 * U'
    //
    // Combined with fixed-point (shift by 10 = divide by 1024):
    // Y scale: 255/219 * 1024 ≈ 1192
    // UV scale: 255/224 ≈ 1.138, so coefficients become:
    // R coeff for V: 1.5748 * 1.138 * 1024 ≈ 1836
    // G coeff for U: 0.1873 * 1.138 * 1024 ≈ 218
    // G coeff for V: 0.4681 * 1.138 * 1024 ≈ 545
    // B coeff for U: 1.8556 * 1.138 * 1024 ≈ 2160
    
    let y_i = y as i32 - 16;
    let u_i = u as i32 - 128;
    let v_i = v as i32 - 128;

    // Scale Y from limited to full range, apply matrix
    let y_scaled = (y_i * 1192) >> 10;  // Expands Y from [16,235] to [0,255]
    
    let r = y_scaled + ((1836 * v_i) >> 10);
    let g = y_scaled - ((218 * u_i + 545 * v_i) >> 10);
    let b = y_scaled + ((2160 * u_i) >> 10);

    (
        r.clamp(0, 255) as u8,
        g.clamp(0, 255) as u8,
        b.clamp(0, 255) as u8,
    )
}
use quinn::{Endpoint, ServerConfig};
use rustls::{Certificate, PrivateKey};
use tokio::sync::mpsc;
use tracing::{debug, error, info, warn, Level};
use tracing_subscriber::FmtSubscriber;

/// Frame header size in bytes
const FRAME_HEADER_SIZE: usize = 26;
/// Maximum payload size we will accept (matches shared protocol's intent; keep conservative).
const MAX_FRAME_PAYLOAD_SIZE: usize = 16 * 1024 * 1024;

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

/// Get screen dimensions for fullscreen mode
#[cfg(windows)]
fn get_screen_dimensions() -> Option<(usize, usize)> {
    unsafe {
        use windows::Win32::UI::WindowsAndMessaging::{GetSystemMetrics, SM_CXSCREEN, SM_CYSCREEN};
        let width = GetSystemMetrics(SM_CXSCREEN) as usize;
        let height = GetSystemMetrics(SM_CYSCREEN) as usize;
        if width > 0 && height > 0 {
            Some((width, height))
        } else {
            None
        }
    }
}

#[cfg(not(windows))]
fn get_screen_dimensions() -> Option<(usize, usize)> {
    None
}

/// Set window to true fullscreen by removing all decorations and positioning at (0,0)
#[cfg(windows)]
fn set_window_fullscreen(window: &Window) {
    unsafe {
        use windows::core::w;
        
        // Find the window by searching for our window title
        let hwnd = FindWindowW(None, w!("ThunderMirror - Waiting for stream..."));
        
        if hwnd.0 != 0 {
            // Remove all window decorations by modifying window style
            let current_style = GetWindowLongW(hwnd, GWL_STYLE);
            let styles_to_remove = WS_CAPTION.0 | WS_THICKFRAME.0 | WS_MINIMIZEBOX.0 | 
                                   WS_MAXIMIZEBOX.0 | WS_SYSMENU.0 | WS_BORDER.0 | WS_DLGFRAME.0;
            let new_style = current_style & !(styles_to_remove as i32);
            SetWindowLongW(hwnd, GWL_STYLE, new_style);
            
            // Get the monitor info for accurate fullscreen
            let monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY);
            let mut mi = MONITORINFO {
                cbSize: std::mem::size_of::<MONITORINFO>() as u32,
                ..Default::default()
            };
            
            if GetMonitorInfoW(monitor, &mut mi).as_bool() {
                let width = mi.rcMonitor.right - mi.rcMonitor.left;
                let height = mi.rcMonitor.bottom - mi.rcMonitor.top;
                
                // Position window at monitor origin with full size, topmost
                // SWP_FRAMECHANGED is needed to apply the style changes
                let _ = SetWindowPos(
                    hwnd,
                    HWND_TOPMOST,
                    mi.rcMonitor.left,
                    mi.rcMonitor.top,
                    width,
                    height,
                    SWP_SHOWWINDOW | SWP_FRAMECHANGED,
                );
            }
        }
    }
    // Suppress unused warning on non-windows
    let _ = window;
}

#[cfg(not(windows))]
fn set_window_fullscreen(_window: &Window) {
    // No-op on non-Windows
}

fn resize_window_and_buffers(
    _window: &mut Window,
    width: &mut usize,
    height: &mut usize,
    buffer: &mut Vec<u32>,
    new_width: usize,
    new_height: usize,
) {
    if new_width == 0 || new_height == 0 {
        return;
    }

    if new_width != *width || new_height != *height {
        *width = new_width;
        *height = new_height;
        buffer.resize(*width * *height, 0);

        // Note: minifb 0.28 doesn't support programmatic window resizing after creation.
        // The buffer will be scaled to fit the current window size.
        info!("Resolution changed to {}x{}", *width, *height);
    }
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
    if args.fullscreen {
        info!("Press Escape to exit fullscreen");
    }

    // Create tokio runtime
    let rt = tokio::runtime::Runtime::new()?;

    // Run QUIC server in background and receive frames
    // Larger buffer to handle frame bursts and prevent backpressure
    let (tx, mut rx) = mpsc::channel::<FrameData>(60);

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

    let (window_width, window_height) = if args.fullscreen {
        // Get the primary monitor dimensions for true fullscreen
        get_screen_dimensions().unwrap_or((width, height))
    } else {
        (width, height)
    };

    let window_opts = if args.fullscreen {
        WindowOptions {
            resize: false,
            borderless: true,
            topmost: true,
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
        window_width,
        window_height,
        window_opts,
    )?;

    // For true fullscreen, position window at (0,0) to cover entire screen
    if args.fullscreen {
        set_window_fullscreen(&window);
    }

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

            // Resize window + buffer if sender resolution changed.
            resize_window_and_buffers(
                &mut window,
                &mut width,
                &mut height,
                &mut buffer,
                new_width,
                new_height,
            );

            match frame.frame_type {
                FrameType::H264 => {
                    // Decode H.264 frame
                    match h264_decoder.decode(&frame.rgba_data) {
                        Ok(Some(decoded)) => {
                            // Get dimensions from decoded frame
                            let (dec_width, dec_height) = decoded.dimensions();

                            // If decoder output dims differ from header, trust decoder.
                            resize_window_and_buffers(
                                &mut window,
                                &mut width,
                                &mut height,
                                &mut buffer,
                                dec_width,
                                dec_height,
                            );

                            // Convert YUV to RGB directly to u32 buffer using BT.709 full range
                            // This gives much better color accuracy than write_rgb8()
                            let y_plane = decoded.y();
                            let u_plane = decoded.u();
                            let v_plane = decoded.v();
                            let y_stride = decoded.strides().0;
                            let u_stride = decoded.strides().1;
                            let v_stride = decoded.strides().2;

                            for row in 0..dec_height {
                                for col in 0..dec_width {
                                    let y_idx = row * y_stride + col;
                                    // U and V are subsampled 2x2 (YUV 4:2:0)
                                    let uv_row = row / 2;
                                    let uv_col = col / 2;
                                    let u_idx = uv_row * u_stride + uv_col;
                                    let v_idx = uv_row * v_stride + uv_col;

                                    let y = y_plane[y_idx];
                                    let u = u_plane[u_idx];
                                    let v = v_plane[v_idx];

                                    let (r, g, b) = yuv_to_rgb_bt709_limited(y, u, v);
                                    
                                    let pixel_idx = row * dec_width + col;
                                    if pixel_idx < buffer.len() {
                                        buffer[pixel_idx] = ((r as u32) << 16) | ((g as u32) << 8) | (b as u32);
                                    }
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
                    let max_pixels = buffer.len().min(frame.rgba_data.len() / 4);
                    for i in 0..max_pixels {
                        let base = i * 4;
                        let r = frame.rgba_data[base] as u32;
                        let g = frame.rgba_data[base + 1] as u32;
                        let b = frame.rgba_data[base + 2] as u32;
                        buffer[i] = (r << 16) | (g << 8) | b;
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
            let codec = if h264_frames > raw_frames {
                "H.264"
            } else {
                "raw"
            };
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
    // macOS uses Network.framework's QUIC via NWConnection, which commonly maps to a
    // client-initiated bidirectional stream rather than per-frame unidirectional streams.
    //
    // To maximize interop, accept BOTH uni and bi streams. For bi streams, parse a continuous
    // byte stream containing repeated (header + payload) frames.

    let conn_bi = conn.clone();
    let conn_uni = conn.clone();
    let conn_dgram = conn;

    let tx_bi = tx.clone();
    let bi_task = tokio::spawn(async move {
        loop {
            match conn_bi.accept_bi().await {
                Ok((_send, mut recv)) => {
                    info!("Accepted bidirectional stream; starting frame parser");
                    if let Err(e) = handle_frame_byte_stream(&mut recv, tx_bi.clone()).await {
                        warn!("Bidirectional stream handler error: {}", e);
                    }
                }
                Err(e) => {
                    info!("Connection closed (bi accept): {}", e);
                    break;
                }
            }
        }
    });

    let tx_uni = tx.clone();
    let uni_task = tokio::spawn(async move {
        loop {
            match conn_uni.accept_uni().await {
                Ok(mut recv) => {
                    // Legacy path: one frame per unidirectional stream.
                    let data = match recv
                        .read_to_end(MAX_FRAME_PAYLOAD_SIZE + FRAME_HEADER_SIZE)
                        .await
                    {
                        Ok(d) => d,
                        Err(e) => {
                            warn!("Failed reading uni stream: {}", e);
                            continue;
                        }
                    };

                    if data.len() < FRAME_HEADER_SIZE {
                        warn!("Received uni data too small for header");
                        continue;
                    }

                    if let Err(e) = handle_single_frame_datagramlike(data, tx_uni.clone()).await {
                        warn!("Failed to parse uni frame: {}", e);
                    }
                }
                Err(e) => {
                    info!("Connection closed (uni accept): {}", e);
                    break;
                }
            }
        }
    });

    // macOS Network.framework's QUIC integration may deliver application data via QUIC DATAGRAMS
    // when using NWConnection.send(content:...). Support that as well for maximum interop.
    let tx_dgram = tx;
    let dgram_task = tokio::spawn(async move {
        loop {
            match conn_dgram.read_datagram().await {
                Ok(dgram) => {
                    // Datagram should contain exactly one frame (header + payload).
                    if let Err(e) =
                        handle_single_frame_datagramlike(dgram.to_vec(), tx_dgram.clone()).await
                    {
                        debug!("Failed to parse datagram frame: {}", e);
                    }
                }
                Err(e) => {
                    info!("Connection closed (datagram recv): {}", e);
                    break;
                }
            }
        }
    });

    // Wait for either accept loop to finish (connection closed).
    let _ = tokio::join!(bi_task, uni_task, dgram_task);
    Ok(())
}

async fn handle_single_frame_datagramlike(
    data: Vec<u8>,
    tx: mpsc::Sender<FrameData>,
) -> anyhow::Result<()> {
    // Parse frame header (big-endian)
    let mut bytes = Bytes::from(data);
    let _version = bytes.get_u8();
    let frame_type_raw = bytes.get_u8();
    let sequence = bytes.get_u64();
    let _timestamp_us = bytes.get_u64();
    let width = bytes.get_u16();
    let height = bytes.get_u16();
    let payload_size = bytes.get_u32() as usize;

    if payload_size > MAX_FRAME_PAYLOAD_SIZE {
        anyhow::bail!("Payload too large: {} bytes", payload_size);
    }

    // Parse frame type
    let frame_type = FrameType::try_from(frame_type_raw)?;

    if bytes.remaining() < payload_size {
        anyhow::bail!(
            "Payload size mismatch: expected {}, got {}",
            payload_size,
            bytes.remaining()
        );
    }

    let rgba_data = bytes.slice(..payload_size).to_vec();

    debug!(
        "Received frame (uni): seq={}, type={:?}, {}x{}, {} bytes",
        sequence, frame_type, width, height, payload_size
    );

    tx.send(FrameData {
        width,
        height,
        rgba_data,
        sequence,
        frame_type,
    })
    .await
    .map_err(|_| anyhow::anyhow!("Frame channel closed"))?;

    Ok(())
}

async fn handle_frame_byte_stream(
    recv: &mut quinn::RecvStream,
    tx: mpsc::Sender<FrameData>,
) -> anyhow::Result<()> {
    use bytes::BytesMut;

    let mut buf = BytesMut::with_capacity(256 * 1024);

    loop {
        // Ensure we have enough to parse at least a header.
        while buf.len() < FRAME_HEADER_SIZE {
            match recv.read_chunk(64 * 1024, true).await? {
                Some(chunk) => buf.extend_from_slice(&chunk.bytes),
                None => return Ok(()), // EOF
            }
        }

        // Peek header without consuming until payload is present.
        let mut header_bytes = Bytes::copy_from_slice(&buf[..FRAME_HEADER_SIZE]);
        let version = header_bytes.get_u8();
        let frame_type_raw = header_bytes.get_u8();
        let sequence = header_bytes.get_u64();
        let _timestamp_us = header_bytes.get_u64();
        let _width = header_bytes.get_u16();
        let _height = header_bytes.get_u16();
        let payload_size = header_bytes.get_u32() as usize;

        if version != 1 {
            anyhow::bail!("Unsupported protocol version: {}", version);
        }

        if payload_size > MAX_FRAME_PAYLOAD_SIZE {
            anyhow::bail!("Payload too large: {} bytes", payload_size);
        }

        let total_needed = FRAME_HEADER_SIZE + payload_size;

        // Read until full frame present.
        while buf.len() < total_needed {
            match recv.read_chunk(256 * 1024, true).await? {
                Some(chunk) => buf.extend_from_slice(&chunk.bytes),
                None => return Ok(()), // EOF mid-frame; just stop
            }
        }

        // Now we can consume this full frame from buf.
        let mut frame_bytes = buf.split_to(total_needed).freeze();
        let _version2 = frame_bytes.get_u8();
        let frame_type_raw2 = frame_bytes.get_u8();
        let sequence2 = frame_bytes.get_u64();
        let _timestamp_us2 = frame_bytes.get_u64();
        let width2 = frame_bytes.get_u16();
        let height2 = frame_bytes.get_u16();
        let payload_size2 = frame_bytes.get_u32() as usize;

        if payload_size2 != payload_size
            || frame_type_raw2 != frame_type_raw
            || sequence2 != sequence
        {
            debug!("Frame header changed between peek/consume; continuing with consumed header");
        }

        let frame_type = match FrameType::try_from(frame_type_raw2) {
            Ok(ft) => ft,
            Err(e) => {
                warn!("Invalid frame type in stream: {}", e);
                continue;
            }
        };

        if frame_bytes.remaining() < payload_size2 {
            warn!(
                "Stream payload size mismatch: expected {}, got {}",
                payload_size2,
                frame_bytes.remaining()
            );
            continue;
        }

        let rgba_data = frame_bytes.split_to(payload_size2).to_vec();

        debug!(
            "Received frame (bi): seq={}, type={:?}, {}x{}, {} bytes",
            sequence2, frame_type, width2, height2, payload_size2
        );

        if tx
            .send(FrameData {
                width: width2,
                height: height2,
                rgba_data,
                sequence: sequence2,
                frame_type,
            })
            .await
            .is_err()
        {
            return Ok(());
        }
    }
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

    // Configure transport for high-bandwidth low-latency streaming
    let mut transport = quinn::TransportConfig::default();
    transport.datagram_receive_buffer_size(Some(16 * 1024 * 1024));
    
    // Increase stream receive window for high-bandwidth streaming
    transport.receive_window((16u32 * 1024 * 1024).try_into().unwrap());
    transport.stream_receive_window((8u32 * 1024 * 1024).try_into().unwrap());
    
    // Keep connection alive
    transport.keep_alive_interval(Some(Duration::from_secs(5)));
    transport.max_idle_timeout(Some(Duration::from_secs(60).try_into().unwrap()));
    
    server_config.transport = Arc::new(transport);

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
