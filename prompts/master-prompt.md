# Master Prompt — Thunderbolt Second Monitor (Mac → Windows) (Free/Open Source)

You are Cursor Agent acting as a principal software engineer. Create an open-source project that lets a **MacBook (M1, 2022, 16GB)** use a **Windows Razer Blade 18 (RTX 4090)** laptop as a **wired display target** over a **Thunderbolt (USB-C connector) link**.

Primary goal (v1): **Mirror** the Mac screen to the Windows laptop over a **wired Thunderbolt Bridge network link** with low latency.
Stretch goal (v2): **Extend** (virtual display) on macOS — treat as *experimental* and isolate behind flags.

Non-goals (for now):
- No mouse/keyboard backchannel
- No audio

Hard requirements:
- Must be **free to run** (no paid dependencies). Use permissive OSS deps only.
- Must be viable to **open source** (MIT license).
- Must be runnable via “clone repo on each machine + run one script per machine”.
- Must include a clear runbook listing every permission prompt and manual step.
- Must include a Cursor workflow: `.cursor/commands/next-step.md` drives phased execution, uses SSH MCP to test, and auto-pushes on success.
- Must include GitHub CI for linting + build errors (Swift + Rust + Windows build).

---

## 0) Deliverables Checklist (create all of this)

### Repo structure
- `shared/` — Rust crate: streaming protocol + transport + stats + logging utilities
- `mac/` — Swift (CLI first; UI later) sender: capture + encode + send
- `win/` — Windows receiver: receive + decode + render
- `scripts/` — one-command scripts for setup, link checks, run, smoke tests
- `.cursor/` — MCP config + Cursor commands
- `.github/workflows/ci.yml` — CI: lint + build
- `docs/` — setup guides, troubleshooting, architecture, phases

### Must-have docs/files
- `README.md` (quickstart)
- `LICENSE` (MIT)
- `CONTRIBUTING.md`
- `docs/ARCHITECTURE.md`
- `docs/PHASE.md` (single source of truth for progress)
- `docs/RUNBOOK.md` (permissions + steps)
- `docs/SETUP_THUNDERBOLT_BRIDGE.md`
- `docs/SSH_MCP_SETUP.md`
- `docs/TESTING.md`
- `docs/TROUBLESHOOTING.md`

---

## 1) Engineering Decisions (fixed)

### Transport
Treat the Thunderbolt cable as **networking** via Thunderbolt Bridge (IP interface). The project assumes:
- Phase 0 uses `ping` + optional `iperf3` verification
- Phase 1+ uses QUIC (preferred) or UDP+reliability fallback

### Video pipeline
- Phase 1: generated test frames (no capture) → validate transport, stats
- Phase 2: ScreenCaptureKit capture (mirror) → send frames (raw or lightly compressed) → Windows renders
- Phase 3: VideoToolbox H.264 low-latency encode → QUIC → Windows Media Foundation HW decode → render fullscreen

### Extend mode (experimental)
If virtual display creation requires fragile/private APIs, isolate behind:
- build flag `EXTEND_EXPERIMENTAL`
- runtime flag `--mode extend`
- clear docs on fragility and fallback to mirror

### Logging
Always log to `logs/` on both sides with timestamps, plus console summary.

---

## 2) Phases (must be executed progressively using Cursor commands)

Create an expanded plan in `docs/PHASE.md` with:
- `PHASE=<0-4>`
- per-phase checklist items that are **small** and **testable**
- each checklist item has “Acceptance check” text
- a “Current focus” section listing the next unchecked item

Phases:
- Phase 0: Wired link + bootstrap tooling (Thunderbolt Bridge + SSH)
- Phase 1: QUIC connection + test pattern streaming + stats
- Phase 2: Real capture MIRROR MVP (correctness first)
- Phase 3: Low-latency H.264 encode/decode + stability polish
- Phase 4: Experimental EXTEND mode (virtual display) + fallback

IMPORTANT:
- In this initial pass, you MUST fully implement **Phase 0** only.
- Do NOT implement Phase 1–4 yet. Only scaffold files/folders and phase checklists.

---

## 3) One-time Bootstrap Scripts (Thunderbolt Bridge + SSH + MCP)

Create these files:

### 3.1 “Connect first” checklist
- `scripts/00_connect_first.md`
  - Instruct user to plug Thunderbolt cable first
  - Verify Thunderbolt Bridge interface on macOS
  - Verify Thunderbolt/USB4 networking adapter on Windows
  - Run link checks before any SSH/MCP steps
  - If ping fails: stop and fix link

### 3.2 Link check scripts (Phase 0 acceptance)
- `scripts/check_link_mac.sh`
- `scripts/check_link_win.ps1`

They must:
- print detected interface name + IPv4
- attempt ping to the other host (accept host/IP as argument or read from env)
- print clear OK/FAIL output and common fixes

### 3.3 SSH server setup on Windows (Admin)
- `scripts/01_setup_ssh_win.ps1`

Requirements:
- Must require Admin/elevated PowerShell; if not, exit with instructions.
- Must detect Thunderbolt/USB4 networking adapter (best-effort).
- Must optionally set a recommended static IP if missing:
  - default: Windows Thunderbolt IP `192.168.50.2/24`
  - prompt user; allow skip
- Must install/enable OpenSSH Server if missing, start `sshd`, set to auto-start.
- Must open Windows Firewall for inbound TCP 22 on the Thunderbolt network profile (best effort).
- Must print next steps:
  - “Now go to Mac and run scripts/01_setup_ssh_mac.sh”
  - show the detected Windows Thunderbolt IP

### 3.4 SSH key + host alias setup on Mac + push key to Windows
- `scripts/01_setup_ssh_mac.sh`

Requirements:
- MUST check Thunderbolt Bridge exists and has IPv4; if not, stop and point to `00_connect_first.md`.
- Prompt interactively for:
  - Windows IP (default `192.168.50.2`)
  - Windows username (required)
- Optionally set recommended static IP on macOS Thunderbolt Bridge:
  - default: Mac Thunderbolt IP `192.168.50.1/24`
  - prompt user; allow skip
- Create dedicated SSH key if missing:
  - `~/.ssh/blade18_tb_ed25519`
- Create/update `~/.ssh/config` host alias:
  - `Host blade18-tb`
  - `HostName <windows_ip>`
  - `User <windows_user>`
  - `IdentityFile ~/.ssh/blade18_tb_ed25519`
  - `IdentitiesOnly yes`
  - keepalive options
- Push the public key to Windows automatically:
  - create `%USERPROFILE%\.ssh` and append to `authorized_keys`
  - use remote PowerShell command via first-time SSH
- Validate: `ssh blade18-tb "whoami"` and print success.

### 3.5 Verify SSH from Mac
- `scripts/02_verify_ssh_mac.sh`

Requirements:
- Runs:
  - `ssh blade18-tb "whoami"`
  - `ssh blade18-tb "powershell.exe -NoProfile -Command \"$PSVersionTable.PSVersion\""`
- Prints concise OK/FAIL + hints.

### 3.6 Auto-generate Cursor MCP config
- `scripts/03_write_cursor_mcp_config.sh`

Requirements:
- Must refuse to proceed unless `ssh blade18-tb "whoami"` succeeds.
- Create `.cursor/` if missing.
- Write `.cursor/mcp.json` defining an SSH MCP server using `npx`, defaulting to:
  - `@aiondadotcom/mcp-ssh@latest`
- Must reference `blade18-tb` host alias (not hardcoded IP).
- Must print next steps:
  - restart Cursor
  - verify MCP connection in Cursor settings
  - if project-level config isn’t detected, print instructions to copy into `~/.cursor/mcp.json`

NOTE:
- If the MCP SSH server expects different env keys/args, adapt accordingly and document it in `docs/SSH_MCP_SETUP.md`.
- Do NOT hardcode secrets in repo.

---

## 4) SSH MCP Setup Docs (Phase 0)

Create/update `docs/SSH_MCP_SETUP.md` with a strict order:

1) Connect cable first (`scripts/00_connect_first.md`)
2) Windows (Admin): `scripts/01_setup_ssh_win.ps1`
3) Mac: `scripts/01_setup_ssh_mac.sh`
4) Mac: `scripts/02_verify_ssh_mac.sh`
5) Mac: `scripts/03_write_cursor_mcp_config.sh`
6) Restart Cursor and verify MCP server is connected

Also include:
- Troubleshooting: firewall, wrong IP, wrong username, SSH service not running
- A “manual steps” fallback if OpenSSH installation fails

---

## 5) Cursor Commands (core workflow)

### 5.1 `.cursor/commands/next-step.md` (required)
Create `.cursor/commands/next-step.md` that behaves as an automated phase driver:

Workflow:
1) Read `docs/PHASE.md` and determine current `PHASE` and the next unchecked item for that phase.
2) Print a short plan describing the single item it will implement.
3) Implement ONLY that one item (small and reviewable).
4) Run local checks depending on what changed:
   - Rust: `cargo fmt --check`, `cargo clippy`, `cargo test` (if shared changed)
   - Swift: `swift build` (if mac changed)
5) Validate Windows side using SSH MCP if available; otherwise use plain `ssh blade18-tb`:
   - run `scripts/check_link_win.ps1`
   - run any phase-relevant Windows smoke tests if they exist
   - collect logs
6) Always validate SSH first:
   - `ssh blade18-tb "whoami"` must succeed, otherwise stop and instruct user to rerun setup scripts.
7) If tests pass:
   - update `docs/PHASE.md` (check off the item)
   - commit with message `phase <n>: <item summary>`
   - push to `origin` (current branch)
   - if push fails due to auth, print the exact command the user must run
8) If tests fail:
   - do NOT commit
   - print a short “Fix Plan” section
   - ensure no long-running background processes remain

### 5.2 `.cursor/commands/ui-step.md` (optional, for Part 2)
Create `.cursor/commands/ui-step.md` that:
- only touches UI code (Phase 3.5+)
- must never break CLI streaming pipeline
- runs minimal UI build checks and commits/pushes on success

---

## 6) Testing Harness (Phase-aligned scripts)

Create (empty/scaffold now; implement later phases progressively):
- `scripts/run_mac.sh` — build & run mac sender CLI
- `scripts/run_win.ps1` — build & run windows receiver
- `scripts/smoke_test_mac.sh` — phase-aware smoke test
- `scripts/smoke_test_win.ps1` — phase-aware smoke test

For Phase 0, smoke tests may just validate:
- link check passes
- SSH check passes
- logs folder creation works

Document in `docs/TESTING.md`.

---

## 7) GitHub CI (lint + build errors)

Create `.github/workflows/ci.yml` to run on pushes + PRs with jobs:

1) `rust` (ubuntu-latest):
- `cargo fmt --all -- --check`
- `cargo clippy --all-targets --all-features -- -D warnings`
- `cargo test --all`
- `cargo build --all`
- add caching for cargo/rust

2) `windows-build` (windows-latest):
- build the Windows receiver target (scaffold okay in Phase 0; ensure workflow won’t be red due to missing code by adding placeholder project or gating steps cleanly)

3) `swift-build` (macos-latest):
- `swift build` (and `swift test` if present)

CI must fail on formatting/lint/build errors and produce actionable logs.

---

## 8) Part 2 — Minimal UI/UX (plan now, build later)

Add a UI track into `docs/PHASE.md` starting after streaming MVP:

Phase 3.5 UI shells (optional but planned):
- macOS SwiftUI app:
  - Start/Stop buttons
  - Windows IP field
  - Mode dropdown (Mirror now; Extend later)
  - status + stats (fps/bitrate/latency estimate)
  - permission helper text for Screen Recording
- Windows viewer UI:
  - Start/Stop
  - status + stats
  - borderless fullscreen toggle

Also add scripts (scaffold now):
- `scripts/run_mac_app.sh`
- `scripts/run_win_app.ps1`

Keep the core CLI path always usable.

---

## 9) Phase 0 Implementation — DO THIS NOW

In this pass, implement Phase 0 end-to-end:

1) Create repo skeleton and all docs listed above (with real, copy/paste steps)
2) Implement:
   - `scripts/00_connect_first.md`
   - `scripts/check_link_mac.sh`
   - `scripts/check_link_win.ps1`
   - `scripts/01_setup_ssh_win.ps1`
