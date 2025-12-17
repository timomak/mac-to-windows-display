# Extend Mode (Experimental) - Research + Plan

## Goal

Make the Mac believe it has an **additional display** so users can arrange the desktop in **Extended** mode, then capture that virtual display and stream it to the Windows receiver.

## Problem Statement

True “extend mode” on macOS requires a real display device (physical or virtual) registered with the WindowServer. Without that, we can only **mirror** an existing display or capture a region/window — which is not the same as a second monitor in System Settings → Displays.

## What we found (macOS 15 / Sequoia)

- The macOS 15 SDK exports Objective‑C classes named `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, etc. (seen in `CoreGraphics.tbd`), and QuartzCore similarly exposes “virtual display” constants in its exported interface list.
- However, **Apple does not ship public headers** for these symbols in the macOS SDK headers.
  - That strongly suggests these APIs are **private SPI** (or internal plumbing for features like AirPlay/Sidecar), and not safe/stable to call directly from an open-source project without reverse engineering.

## Approaches

### Option A: Use private CoreGraphics/QuartzCore SPI (CGVirtualDisplay / CGS*)

- **Pros**: Might enable a true virtual display without writing a driver.
- **Cons**:
  - Undocumented and unstable across OS releases.
  - Higher risk of breakage on updates (your macOS 15.6.1 note is a good example of why this matters).
  - Not appropriate for App Store distribution; can trip system integrity / code signing expectations.
- **Status**: Not implemented. We intentionally avoid calling private SPI in this repo right now.

### Option B: Implement a virtual display driver (DriverKit + system extension)

- **Pros**:
  - The most “correct” long-term path for a supported virtual monitor.
  - Similar in spirit to how DisplayLink-style solutions work.
- **Cons**:
  - Significant scope: DriverKit display stack, entitlement/signing, system extension install flow, compatibility testing.
  - Requires more complex build/deploy tooling and user onboarding steps.
- **Status**: Chosen long-term direction if we want “real” Extend Mode.

### Option C: “Pseudo-extend” UI window on Mac

- Create a borderless window and ask the user to drag apps into it.
- **Not a real display**: it won’t appear as a separate monitor in Displays settings; spaces/menubar behavior differs.
- **Status**: Not pursued as Phase 4 goal (it doesn’t meet the requirement).

## Current Implementation (Phase 4 deliverable)

- `--mode extend` is accepted and **gated** behind:
- Runtime flag: `--enable-extend-experimental` (controls whether we attempt virtual display creation)
- Build flag: `-Xswiftc -DEXTEND_EXPERIMENTAL` (required to compile any virtual-display attempt code)

### Usable extend today (no driver required)

Even without a true “virtual monitor”, Extend Mode is usable by capturing a **secondary display**:

- If your Mac already has a second monitor, `--mode extend` will capture it by default.
- If you don’t have a second monitor, a cheap **HDMI dummy plug** (or any extra display adapter) can create a second display to extend onto.

The sender will:

- Prefer a virtual display (only if `--enable-extend-experimental` and built with `-DEXTEND_EXPERIMENTAL`)
- Otherwise capture a secondary display (if present)
- Otherwise fall back to mirror (configurable with `--extend-fallback`)

### Relevant flags

- `--capture-display main|secondary`
- `--capture-display-id <CGDirectDisplayID>`
- `--extend-fallback secondary|mirror|fail`

This keeps the CLI pipeline stable and makes the next step (DriverKit-based virtual display) an additive effort.

## Next Step (for real Extend Mode)

- Add a new macOS target for a DriverKit-based virtual display (system extension).
- Provide install/uninstall scripts + runbook steps.
- On success:
  - Create a virtual display with requested resolution/refresh.
  - Capture that display via ScreenCaptureKit using its `displayID`.
  - Stream to Windows as today.


