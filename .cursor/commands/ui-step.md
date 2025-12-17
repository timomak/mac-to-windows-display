# UI Step - UI Development Command

This command implements UI-specific changes **one PHASE at a time** (Phase 3.5+).

## Instructions for Cursor Agent

When this command is invoked:

### 1. Verify CLI Pipeline Works (Pre-flight)

Before any UI changes, ensure the core CLI streaming pipeline builds:

```bash
# Quick sanity check
cd shared && cargo check
cd mac && swift build
```

If CLI is broken, **STOP**. Fix CLI first before UI work.

### 2. Identify the Current UI Phase (Do ONE phase at a time)

Open `docs/PHASE.md` and determine the **next incomplete UI phase** (starting at Phase 3.5, then Phase 4, etc.).

- **Rule**: Do not start work from a later phase if an earlier UI phase still has unchecked items.
- **Scope**: Only implement checklist items that belong to the selected phase.

### 3. Implement UI Items Until the Phase Is Complete

Within the selected phase:

- Pick the **highest-priority unchecked item** in that phase.
- Implement it fully (including error handling / status text as needed).
- Repeat until **all items in the phase are checked off**.

Only touch UI-related code:
- macOS: SwiftUI views in `mac/Sources/ThunderMirrorApp/`
- Windows: UI code in `win/src/ui/`

**IMPORTANT:** Never break the CLI streaming pipeline. UI is an optional wrapper.

### 4. Run UI Build Checks (Each completed item, and at phase completion)

**macOS:**

```bash
cd mac && swift build
```

**Windows (via SSH):**

```bash
ssh blade18-tb "cd project && cargo build --release"
```

### 5. On Success (Per Item + Per Phase)

- **After each item**: update `docs/PHASE.md` and check off that item.
- **After finishing the phase**:
  - Ensure all items in that phase are checked.
  - Commit with message:

```
phase <X> ui: complete phase checklist
```

Where `<X>` is the phase number (e.g., `3.5`).

- Push to origin.

### 6. On Failure

1. Do NOT commit
2. Explain what failed
3. Suggest fix
4. Ensure CLI still works (rollback if needed)

## UI Development Guidelines

### macOS SwiftUI App

- Keep UI simple and functional
- Use native macOS controls
- Handle Screen Recording permission gracefully
- Show clear status and error messages

Basic structure:

```swift
// mac/Sources/ThunderMirrorApp/
//   - ThunderMirrorApp.swift (main entry)
//   - ContentView.swift (main UI)
//   - StatusView.swift (connection status)
//   - SettingsView.swift (configuration)
```

### Windows Viewer UI

- Use native Windows controls (Win32 or WinUI)
- Fullscreen/windowed toggle
- Status bar with stats
- Minimal chrome for actual display

## Notes

- UI is optional - CLI must always work
- Test both CLI and UI after changes
- UI changes should not affect streaming performance
- Keep UI responsive (don't block on network)
