# UI Step - UI Development Command

This command implements UI-specific changes (Phase 3.5+).

## Instructions for Cursor Agent

When this command is invoked:

### 1. Verify CLI Pipeline Works

Before any UI changes, ensure the core CLI streaming works:
```bash
# Quick sanity check
cd shared && cargo check
cd mac && swift build
```

If CLI is broken, STOP. Fix CLI first before UI work.

### 2. Read UI Items from PHASE.md

Check `docs/PHASE.md` for Phase 3.5 UI checklist items.

### 3. Implement ONE UI Item

Only touch UI-related code:
- macOS: SwiftUI views in mac/Sources/ThunderMirrorApp/
- Windows: UI code in win/src/ui/

**IMPORTANT:** Never break the CLI streaming pipeline. UI is optional wrapper.

### 4. Run UI Build Checks

**macOS:**
```bash
cd mac && swift build
```

**Windows (via SSH):**
```bash
ssh blade18-tb "cd project && cargo build --release"
```

### 5. On Success

1. Update docs/PHASE.md - check off UI item
2. Commit with message:
   ```
   phase 3.5 ui: <brief description>
   ```
3. Push to origin

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
