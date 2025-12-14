# Contributing to ThunderMirror

Thank you for your interest in contributing! This project aims to create an open-source, free solution for using a Windows laptop as a wired display for a Mac over Thunderbolt.

## Getting Started

1. Read the [README](README.md) for project overview
2. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for technical design
3. Check [docs/PHASE.md](docs/PHASE.md) for current progress and next steps

## Development Setup

### Prerequisites

**Mac (Sender):**
- macOS 13+ (Ventura or later)
- Xcode Command Line Tools (`xcode-select --install`)
- Rust toolchain (`curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`)

**Windows (Receiver):**
- Windows 10/11
- Visual Studio 2022 with C++ workload
- Rust toolchain (https://rustup.rs)

### Clone and Setup

```bash
# Clone the repo on both machines
git clone https://github.com/YOUR_USERNAME/mac-to-windows-display.git
cd mac-to-windows-display

# On Mac: Run setup
./scripts/01_setup_ssh_mac.sh

# On Windows (Admin PowerShell): Run setup
.\scripts\01_setup_ssh_win.ps1
```

## Development Workflow

### Using Cursor Commands

This project uses Cursor IDE with automated phase-driven development:

1. Open the project in Cursor
2. Use `.cursor/commands/next-step.md` to implement the next checklist item
3. The command will build, test, and push on success

### Manual Development

```bash
# Rust shared library
cd shared && cargo fmt && cargo clippy && cargo test

# Swift Mac CLI
cd mac && swift build

# Windows receiver
cd win && cargo build
```

## Code Style

### Rust
- Use `cargo fmt` for formatting
- Use `cargo clippy` for linting
- All warnings treated as errors in CI

### Swift
- Follow Swift API Design Guidelines
- Use SwiftLint if available

## Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes with clear, atomic commits
4. Ensure CI passes (lint + build)
5. Submit a PR with a clear description

### Commit Message Format

```
phase <N>: <brief description>

<optional longer explanation>
```

Example:
```
phase 1: add QUIC transport layer

Implements quinn-based QUIC connection with:
- Server/client handshake
- Frame chunking
- Basic error handling
```

## Testing

See [docs/TESTING.md](docs/TESTING.md) for detailed testing procedures.

Quick smoke tests:
```bash
# Mac
./scripts/smoke_test_mac.sh

# Windows (PowerShell)
.\scripts\smoke_test_win.ps1
```

## Reporting Issues

When reporting issues, please include:
- OS version (macOS version / Windows build)
- Hardware (Mac model, Windows laptop model)
- Thunderbolt adapter/cable being used
- Relevant logs from `logs/` folder
- Steps to reproduce

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
