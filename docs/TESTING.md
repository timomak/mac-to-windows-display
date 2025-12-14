# Testing Guide

This document describes how to test ThunderMirror at each development phase.

## Quick Reference

```bash
# Mac smoke test
./scripts/smoke_test_mac.sh

# Windows smoke test (PowerShell)
.\scripts\smoke_test_win.ps1

# Run Mac sender
./scripts/run_mac.sh

# Run Windows receiver (PowerShell)
.\scripts\run_win.ps1
```

## Phase-Specific Tests

### Phase 0: Link and SSH

**Mac:**
```bash
# Check Thunderbolt link
./scripts/check_link_mac.sh

# Verify SSH to Windows
./scripts/02_verify_ssh_mac.sh

# Full Phase 0 smoke test
./scripts/smoke_test_mac.sh
```

**Windows (PowerShell):**
```powershell
# Check Thunderbolt link
.\scripts\check_link_win.ps1

# Full Phase 0 smoke test
.\scripts\smoke_test_win.ps1
```

**Expected Results:**
- ✅ Thunderbolt interface detected on both machines
- ✅ Both machines have IPs in same subnet
- ✅ Ping succeeds in both directions (<1ms)
- ✅ SSH from Mac to Windows works
- ✅ logs/ directory exists

### Phase 1: QUIC + Test Patterns

*Coming in Phase 1 implementation*

Tests will verify:
- QUIC connection establishes
- Test pattern frames are sent (60 fps target)
- Windows receives and renders frames
- Stats show reasonable FPS and latency

### Phase 2: Real Capture

*Coming in Phase 2 implementation*

Tests will verify:
- ScreenCaptureKit permission granted
- Screen capture works at target resolution
- Frames are received on Windows
- Screen content matches (visual verification)

### Phase 3: H.264 Pipeline

*Coming in Phase 3 implementation*

Tests will verify:
- VideoToolbox encoder initializes
- Media Foundation decoder initializes
- End-to-end latency <50ms
- Stable streaming for 60+ seconds

## Smoke Test Details

### Mac Smoke Test (`smoke_test_mac.sh`)

The Mac smoke test checks:

1. **Thunderbolt Bridge exists**
   - Interface named "Thunderbolt Bridge" or similar
   - Has valid IPv4 address

2. **Ping to Windows succeeds**
   - Uses IP from environment or default 192.168.50.2
   - At least 3 successful pings

3. **SSH connection works** (if Phase 0+ setup complete)
   - `ssh blade18-tb "whoami"` returns username

4. **Build checks** (if source exists)
   - Swift: `swift build` succeeds
   - Rust: `cargo check` in shared/

5. **Logs directory exists**
   - `./logs/` exists and is writable

### Windows Smoke Test (`smoke_test_win.ps1`)

The Windows smoke test checks:

1. **Thunderbolt adapter exists**
   - Network adapter with "Thunderbolt" or "USB4" in name
   - Has valid IPv4 address

2. **Ping to Mac succeeds**
   - Uses IP from environment or default 192.168.50.1
   - At least 3 successful pings

3. **Build checks** (if source exists)
   - Rust: `cargo check` in win/

4. **Logs directory exists**
   - `.\logs\` exists and is writable

## Manual Testing Checklist

### End-to-End Streaming Test

1. Start Windows receiver:
   ```powershell
   .\scripts\run_win.ps1
   ```

2. Start Mac sender:
   ```bash
   ./scripts/run_mac.sh
   ```

3. Observe:
   - [ ] Windows shows video window
   - [ ] Content updates smoothly
   - [ ] No visible tearing or artifacts
   - [ ] Stats show stable FPS

4. Measure latency (visual):
   - Display a timer on Mac
   - Compare with Windows view
   - Latency should be <50ms (hard to perceive)

5. Test duration:
   - [ ] Stable for 1 minute
   - [ ] Stable for 10 minutes
   - [ ] Stable for 1 hour

### Stress Tests

**Bandwidth test:**
```bash
# On Mac
iperf3 -c 192.168.50.2 -t 60 -P 4
```
Should sustain >1 Gbps.

**Reconnection test:**
1. Start streaming
2. Unplug cable
3. Replug within 5 seconds
4. Observe: Should reconnect automatically (Phase 3+)

## CI Tests

The GitHub Actions CI runs:

- **Rust:** `cargo fmt`, `cargo clippy`, `cargo test`, `cargo build`
- **Swift:** `swift build`, `swift test`
- **Windows:** `cargo build` (cross-compile or Windows runner)

See `.github/workflows/ci.yml` for details.

## Log Analysis

All tests write logs to `./logs/`:

```bash
# View latest Mac sender log
tail -f logs/mac_sender_*.log

# View latest Windows receiver log (on Windows)
Get-Content -Wait .\logs\win_receiver_*.log
```

### Log Format

```
2024-01-15T10:30:45.123Z [INFO] [sender] Starting capture...
2024-01-15T10:30:45.456Z [DEBUG] [transport] QUIC connection established
2024-01-15T10:30:46.000Z [INFO] [stats] FPS: 60.2, Bitrate: 45.3 Mbps, Latency: 12ms
```

### Common Log Patterns

| Pattern | Meaning |
|---------|---------|
| `Connection refused` | Windows receiver not running |
| `Permission denied` | Screen Recording permission needed |
| `Encoder error` | VideoToolbox issue |
| `Decoder error` | Media Foundation issue |
| `Frame drop` | Network or processing can't keep up |

## Reporting Test Results

When reporting issues, include:

1. **OS versions:**
   - macOS: `sw_vers`
   - Windows: `winver`

2. **Test command and output**

3. **Log files:**
   - Attach relevant logs from `./logs/`

4. **Hardware:**
   - Mac model
   - Windows PC model
   - Cable used

5. **Screenshots/video** if visual issue
