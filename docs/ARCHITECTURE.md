# Architecture

## Overview

ThunderMirror is a screen streaming solution that uses a direct Thunderbolt cable connection between a Mac (sender) and Windows PC (receiver). The cable creates a point-to-point network link (Thunderbolt Bridge) that we use for high-bandwidth, low-latency video streaming.

```
┌──────────────────┐     Thunderbolt Cable     ┌──────────────────┐
│                  │    (Network over USB-C)   │                  │
│   Mac (Sender)   │◄─────────────────────────►│Windows (Receiver)│
│                  │     192.168.50.1/24       │                  │
│  - Capture       │     192.168.50.2/24       │  - Decode        │
│  - Encode        │                           │  - Render        │
│  - Send          │                           │                  │
└──────────────────┘                           └──────────────────┘
```

## Components

### 1. Shared Library (`shared/`)

A Rust crate containing code used by both sender and receiver:

- **Transport Layer:** QUIC-based networking (using `quinn`)
- **Protocol:** Frame chunking, sequencing, acknowledgments
- **Stats:** FPS, bitrate, latency measurement
- **Logging:** Structured logging to files and console

### 2. Mac Sender (`mac/`)

Swift CLI application (with optional SwiftUI wrapper):

- **Capture:** ScreenCaptureKit for screen capture
- **Encode:** VideoToolbox H.264 hardware encoder
- **Send:** Frames sent over QUIC to Windows

Key files:
- `Sources/ThunderMirror/` - Main Swift source
- `Package.swift` - Swift Package Manager manifest

### 3. Windows Receiver (`win/`)

Rust application:

- **Receive:** QUIC stream receiver
- **Decode:** Media Foundation H.264 hardware decoder
- **Render:** DirectX/Win2D fullscreen rendering

Key files:
- `src/` - Rust source code
- `Cargo.toml` - Rust manifest

## Transport

### Why Thunderbolt Bridge?

Thunderbolt cables support IP networking when connected between two computers. This creates a dedicated network interface:

- **Mac:** "Thunderbolt Bridge" in Network preferences
- **Windows:** "Thunderbolt Networking" or "USB4 Networking" adapter

Benefits:
- No router/switch needed
- Dedicated bandwidth (up to 40 Gbps on Thunderbolt 3/4)
- Very low latency (direct connection)
- More reliable than WiFi

### Protocol: QUIC

We use QUIC (via the `quinn` crate) for:

- **Reliability:** Built-in retransmission for lost packets
- **Low latency:** 0-RTT connection establishment
- **Multiplexing:** Multiple streams without head-of-line blocking
- **Congestion control:** Adapts to available bandwidth

For Phase 1, we may use raw UDP for simpler testing, then upgrade to QUIC.

## Video Pipeline

### Phase 1: Test Patterns
```
Generate Color Bars → Raw Pixels → QUIC → Render
```

### Phase 2: Real Capture (Mirror)
```
ScreenCaptureKit → Raw/Light Compression → QUIC → Render
```

### Phase 3: Hardware Encode/Decode
```
ScreenCaptureKit → VideoToolbox H.264 → QUIC → Media Foundation → DirectX Render
```

### Encoding Settings (Phase 3)

For low-latency streaming, we use:
- **Codec:** H.264 Baseline or Main profile
- **Bitrate:** Adaptive, 20-100 Mbps
- **Latency mode:** Ultra-low latency (no B-frames)
- **GOP:** Very short or all-intra

## Extend Mode (Experimental)

Virtual display creation on macOS requires using private/undocumented APIs or kernel extensions. This is isolated behind:

- Build flag: `EXTEND_EXPERIMENTAL`
- Runtime flag: `--mode extend`

If virtual display fails, the system falls back to mirror mode.

## Logging

All components log to:
- `logs/` directory (timestamped files)
- Console (summary output)

Log format includes:
- Timestamp
- Component
- Level (debug/info/warn/error)
- Message

## Configuration

Configuration is handled through:
- Command-line arguments
- Environment variables
- Optional config file (future)

Default IPs:
- Mac: `192.168.50.1`
- Windows: `192.168.50.2`

## Security Considerations

- Communication is over a direct cable (not internet-exposed)
- QUIC provides TLS 1.3 encryption
- SSH key-based authentication for MCP/remote commands
- No credentials stored in repository
