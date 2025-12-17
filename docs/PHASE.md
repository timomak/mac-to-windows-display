# Development Phases

This document tracks development progress. Each phase builds on the previous one.

**Current Phase:** `PHASE=3.5`

**Current Focus:** macOS SwiftUI app shell (Optional UI phase)

---

## Phase 0: Wired Link + Bootstrap Tooling

**Goal:** Establish reliable Thunderbolt Bridge networking and SSH/MCP tooling.

### Checklist

- [x] Create repository structure
  - *Acceptance:* All directories exist: `shared/`, `mac/`, `win/`, `scripts/`, `docs/`, `.cursor/`, `.github/`

- [x] Create documentation skeleton
  - *Acceptance:* All docs files exist with meaningful content

- [x] Create `scripts/00_connect_first.md` - connection checklist
  - *Acceptance:* File exists with clear step-by-step instructions

- [x] Create `scripts/check_link_mac.sh` - Mac link verification
  - *Acceptance:* Script detects Thunderbolt Bridge, shows IP, pings Windows

- [x] Create `scripts/check_link_win.ps1` - Windows link verification
  - *Acceptance:* Script detects Thunderbolt adapter, shows IP, pings Mac

- [x] Create `scripts/01_setup_ssh_win.ps1` - Windows SSH server setup
  - *Acceptance:* Script installs/enables OpenSSH, opens firewall, prints Mac IP

- [x] Create `scripts/01_setup_ssh_mac.sh` - Mac SSH key + config setup
  - *Acceptance:* Script creates key, configures host alias, pushes key to Windows

- [x] Create `scripts/02_verify_ssh_mac.sh` - SSH verification
  - *Acceptance:* Script tests SSH connection, prints clear OK/FAIL

- [x] Create `scripts/03_write_cursor_mcp_config.sh` - MCP config generator
  - *Acceptance:* Script creates `.cursor/mcp.json` with SSH MCP server config

- [x] Create `.cursor/commands/next-step.md` - phase driver command
  - *Acceptance:* Command reads PHASE.md and implements next item

- [x] Create `.github/workflows/ci.yml` - CI pipeline
  - *Acceptance:* CI runs lint+build for Rust, Swift, Windows; fails on errors

- [x] Scaffold `shared/` Rust crate
  - *Acceptance:* `cargo build` succeeds in `shared/`

- [x] Scaffold `mac/` Swift package
  - *Acceptance:* `swift build` succeeds in `mac/`

- [x] Scaffold `win/` Rust project
  - *Acceptance:* `cargo build` succeeds in `win/`

- [x] Create logs/ directory with .gitkeep
  - *Acceptance:* `logs/` exists and is tracked

---

## Phase 1: QUIC Connection + Test Pattern Streaming + Stats

**Goal:** Establish QUIC transport and stream generated test frames with stats.

### Checklist

- [x] Add quinn QUIC dependency to shared crate
  - *Acceptance:* `cargo build` succeeds with quinn

- [x] Implement basic QUIC server in shared crate
  - *Acceptance:* Unit test shows server accepts connections

- [x] Implement basic QUIC client in shared crate
  - *Acceptance:* Unit test shows client connects to server

- [x] Add frame protocol types (header, payload chunking)
  - *Acceptance:* Types compile, doc comments explain format

- [x] Implement test pattern generator (color bars)
  - *Acceptance:* Function generates valid RGBA buffer

- [x] Mac CLI: Send test patterns over QUIC
  - *Acceptance:* Mac sends 60 fps test pattern stream

- [x] Windows: Receive and render test patterns
  - *Acceptance:* Windows displays color bars in window

- [x] Add stats collection (FPS, bytes/sec, latency estimate)
  - *Acceptance:* Stats logged every second on both sides

- [x] Add smoke test for Phase 1
  - *Acceptance:* `smoke_test_*.sh/ps1` validates streaming works

---

## Phase 2: Real Capture (Mirror MVP)

**Goal:** Capture actual Mac screen and stream to Windows.

### Checklist

- [x] Implement ScreenCaptureKit capture in Mac CLI
  - *Acceptance:* Captures screen at 60 fps

- [x] Handle Screen Recording permission prompt
  - *Acceptance:* App requests permission, docs explain approval

- [x] Send captured frames (raw or lightly compressed)
  - *Acceptance:* Real screen content visible on Windows

- [x] Handle display resolution changes
  - *Acceptance:* Receiver adapts to resolution changes

- [x] Add smoke test for Phase 2
  - *Acceptance:* `smoke_test_*.sh/ps1` validates real capture works

---

## Phase 3: Low-Latency H.264 Encode/Decode + Polish

**Goal:** Hardware-accelerated video codec for low latency.

### Checklist

- [x] Implement VideoToolbox H.264 encoder on Mac
  - *Acceptance:* Encodes at 60 fps with <5ms latency

- [x] Configure encoder for ultra-low latency
  - *Acceptance:* No B-frames, short GOP, baseline profile

- [x] Implement Media Foundation H.264 decoder on Windows
  - *Acceptance:* Decodes stream in real-time (using OpenH264)

- [x] Fullscreen borderless window on Windows
  - *Acceptance:* Viewer fills entire screen

- [x] Add bitrate adaptation
  - *Acceptance:* Adjusts bitrate based on network conditions

- [x] Polish error handling and reconnection
  - *Acceptance:* Graceful recovery from disconnection

- [x] Add comprehensive logging and stats
  - *Acceptance:* `logs/` contains detailed session logs

---

## Phase 3.5: UI Shells (Optional)

**Goal:** Basic UI wrappers for CLI tools.

### Checklist

- [x] macOS SwiftUI app shell
  - *Acceptance:* App builds and shows Start/Stop buttons

- [x] macOS: IP input field
  - *Acceptance:* User can enter Windows IP

- [x] macOS: Mode dropdown (Mirror/Extend)
  - *Acceptance:* Dropdown exists (Extend disabled until Phase 4)

- [x] macOS: Status and stats display
  - *Acceptance:* Shows FPS, bitrate, latency

- [x] Windows viewer UI shell
  - *Acceptance:* App builds with Start/Stop buttons

- [ ] Windows: Status display
  - *Acceptance:* Shows connection status and stats

- [ ] Windows: Fullscreen toggle
  - *Acceptance:* Button toggles borderless fullscreen

---

## Phase 4: Extend Mode (Experimental)

**Goal:** Virtual display support for desktop extension.

### Checklist

- [ ] Research virtual display APIs/approaches
  - *Acceptance:* Doc explaining chosen approach and risks

- [ ] Implement virtual display creation (behind flag)
  - *Acceptance:* `--mode extend` creates virtual display

- [ ] Handle virtual display in capture pipeline
  - *Acceptance:* Virtual display content streams to Windows

- [ ] Add fallback to mirror mode on failure
  - *Acceptance:* Graceful degradation if virtual display fails

- [ ] Document experimental status and limitations
  - *Acceptance:* README and docs clearly mark as experimental

---

## Phase 5: Maximum Performance (Stress Test)

**Goal:** Push the Thunderbolt connection to its limits with maximum resolution, refresh rate, and quality.

### Checklist

- [ ] Support 4K @ 60Hz streaming
  - *Acceptance:* 3840×2160 streams smoothly with <16ms latency

- [ ] Support 4K @ 120Hz streaming
  - *Acceptance:* 3840×2160 @ 120Hz with Thunderbolt's full bandwidth

- [ ] Implement 10-bit color depth (HDR10)
  - *Acceptance:* HDR content preserves wide color gamut

- [ ] Add HEVC/H.265 encoding option
  - *Acceptance:* Better quality at same bitrate vs H.264

- [ ] Benchmark and log bandwidth utilization
  - *Acceptance:* Stats show Gbps throughput, % of Thunderbolt capacity

- [ ] Support 5K resolution (5120×2880)
  - *Acceptance:* Native Retina resolution streams to Windows

- [ ] Adaptive quality scaling under load
  - *Acceptance:* Dynamically adjusts resolution/bitrate to maintain framerate

- [ ] Create performance benchmark suite
  - *Acceptance:* Automated tests measure latency, throughput, dropped frames

- [ ] Document maximum achievable specs
  - *Acceptance:* README lists tested max resolution/fps combinations

---

## Progress Summary

| Phase | Items | Complete | Status |
|-------|-------|----------|--------|
| 0 | 14 | 14 | ✅ Done |
| 1 | 9 | 9 | ✅ Done |
| 2 | 5 | 5 | ✅ Done |
| 3 | 7 | 7 | ✅ Done |
| 3.5 | 7 | 5 | 🔲 Next |
| 4 | 5 | 0 | 🔲 |
| 5 | 9 | 0 | 🔲 |
