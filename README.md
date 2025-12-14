# ThunderMirror 🖥️⚡

**Use a Windows laptop as a wired second monitor for your Mac over Thunderbolt.**

Open-source, free, low-latency screen mirroring (and experimental extending) from macOS to Windows via a direct Thunderbolt/USB4 cable connection.

## Features

- **Mirror Mode (v1):** Stream your Mac display to a Windows laptop over wired Thunderbolt
- **Low Latency:** Direct cable connection with hardware-accelerated encoding/decoding
- **Free & Open Source:** MIT licensed, no paid dependencies
- **Extend Mode (v2, Experimental):** Virtual display support (behind feature flags)

## Hardware Requirements

- **Mac:** Any Mac with Thunderbolt 3/4 or USB4 port (tested on M1 MacBook Pro)
- **Windows PC:** Any Windows laptop/desktop with Thunderbolt 3/4 or USB4 port
- **Cable:** Thunderbolt 3/4 cable (USB-C connectors on both ends)

> ⚠️ USB-C cables that are NOT Thunderbolt-certified may not work for the Thunderbolt Bridge network feature.

## Quick Start

### 1. Connect the Cable First

Plug the Thunderbolt cable between both machines **before** running any scripts.

See [docs/SETUP_THUNDERBOLT_BRIDGE.md](docs/SETUP_THUNDERBOLT_BRIDGE.md) for detailed connection instructions.

### 2. Verify the Link

**On Mac:**
```bash
./scripts/check_link_mac.sh
```

**On Windows (PowerShell):**
```powershell
.\scripts\check_link_win.ps1
```

Both should show the Thunderbolt network interface with an IP address.

### 3. Setup SSH (One-Time)

**On Windows (Admin PowerShell):**
```powershell
.\scripts\01_setup_ssh_win.ps1
```

**On Mac:**
```bash
./scripts/01_setup_ssh_mac.sh
```

### 4. Run ThunderMirror

**On Windows (Receiver):**
```powershell
.\scripts\run_win.ps1
```

**On Mac (Sender):**
```bash
./scripts/run_mac.sh
```

## Project Status

See [docs/PHASE.md](docs/PHASE.md) for current development status.

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Wired link + SSH setup | ✅ |
| 1 | QUIC transport + test patterns | 🔲 |
| 2 | Real capture (Mirror MVP) | 🔲 |
| 3 | H.264 encode/decode + polish | 🔲 |
| 4 | Extend mode (experimental) | 🔲 |

## Documentation

- [Architecture](docs/ARCHITECTURE.md) - Technical design overview
- [Phases](docs/PHASE.md) - Development roadmap and checklist
- [Runbook](docs/RUNBOOK.md) - All permissions and manual steps
- [Thunderbolt Setup](docs/SETUP_THUNDERBOLT_BRIDGE.md) - Cable and network setup
- [SSH/MCP Setup](docs/SSH_MCP_SETUP.md) - SSH and Cursor MCP configuration
- [Testing](docs/TESTING.md) - How to test the project
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and fixes

## Development

### Prerequisites

**Mac:**
- macOS 13+ (Ventura)
- Xcode Command Line Tools
- Rust toolchain

**Windows:**
- Windows 10/11
- Visual Studio 2022 with C++
- Rust toolchain

### Building

```bash
# Rust shared library
cd shared && cargo build

# Swift Mac CLI
cd mac && swift build

# Windows receiver
cd win && cargo build
```

### Cursor IDE Workflow

This project includes Cursor commands for automated development:

1. Open in Cursor IDE
2. Run `.cursor/commands/next-step.md` to implement the next phase item
3. Changes are automatically tested and pushed on success

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by the need for free alternatives to paid display software
- Built with Swift, Rust, and open-source libraries
