# Development Phases

This document tracks development progress. Each phase builds on the previous one.

**Current Phase:** `PHASE=0`

**Current Focus:** Phase 0 complete - ready for Phase 1

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

- [ ] Add quinn QUIC dependency to shared crate
  - *Acceptance:* `cargo build` succeeds with quinn

- [ ] Implement basic QUIC server in shared crate
  - *Acceptance:* Unit test shows server accepts connections

- [ ] Implement basic QUIC client in shared crate
  - *Acceptance:* Unit test shows client connects to server

- [ ] Add frame protocol types (header, payload chunking)
  - *Acceptance:* Types compile, doc comments explain format

- [ ] Implement test pattern generator (color bars)
  - *Acceptance:* Function generates valid RGBA buffer

- [ ] Mac CLI: Send test patterns over QUIC
  - *Acceptance:* Mac sends 60 fps test pattern stream

- [ ] Windows: Receive and render test patterns
  - *Acceptance:* Windows displays color bars in window

- [ ] Add stats collection (FPS, bytes/sec, latency estimate)
  - *Acceptance:* Stats logged every second on both sides

- [ ] Add smoke test for Phase 1
  - *Acceptance:* `smoke_test_*.sh/ps1` validates streaming works

---

## Phase 2: Real Capture (Mirror MVP)

**Goal:** Capture actual Mac screen and stream to Windows.

### Checklist

- [ ] Implement ScreenCaptureKit capture in Mac CLI
  - *Acceptance:* Captures screen at 60 fps

- [ ] Handle Screen Recording permission prompt
  - *Acceptance:* App requests permission, docs explain approval

- [ ] Send captured frames (raw or lightly compressed)
  - *Acceptance:* Real screen content visible on Windows

- [ ] Handle display resolution changes
  - *Acceptance:* Receiver adapts to resolution changes

- [ ] Add smoke test for Phase 2
  - *Acceptance:* `smoke_test_*.sh/ps1` validates real capture works

---

## Phase 3: Low-Latency H.264 Encode/Decode + Polish

**Goal:** Hardware-accelerated video codec for low latency.

### Checklist

- [ ] Implement VideoToolbox H.264 encoder on Mac
  - *Acceptance:* Encodes at 60 fps with <5ms latency

- [ ] Configure encoder for ultra-low latency
  - *Acceptance:* No B-frames, short GOP, baseline profile

- [ ] Implement Media Foundation H.264 decoder on Windows
  - *Acceptance:* Decodes stream in real-time

- [ ] Fullscreen borderless window on Windows
  - *Acceptance:* Viewer fills entire screen

- [ ] Add bitrate adaptation
  - *Acceptance:* Adjusts bitrate based on network conditions

- [ ] Polish error handling and reconnection
  - *Acceptance:* Graceful recovery from disconnection

- [ ] Add comprehensive logging and stats
  - *Acceptance:* `logs/` contains detailed session logs

---

## Phase 3.5: UI Shells (Optional)

**Goal:** Basic UI wrappers for CLI tools.

### Checklist

- [ ] macOS SwiftUI app shell
  - *Acceptance:* App builds and shows Start/Stop buttons

- [ ] macOS: IP input field
  - *Acceptance:* User can enter Windows IP

- [ ] macOS: Mode dropdown (Mirror/Extend)
  - *Acceptance:* Dropdown exists (Extend disabled until Phase 4)

- [ ] macOS: Status and stats display
  - *Acceptance:* Shows FPS, bitrate, latency

- [ ] Windows viewer UI shell
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

## Progress Summary

| Phase | Items | Complete | Status |
|-------|-------|----------|--------|
| 0 | 14 | 14 | ✅ Done |
| 1 | 9 | 0 | 🔲 Next |
| 2 | 5 | 0 | 🔲 |
| 3 | 7 | 0 | 🔲 |
| 3.5 | 7 | 0 | 🔲 |
| 4 | 5 | 0 | 🔲 |
