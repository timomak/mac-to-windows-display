# Build Windows App

Build the ThunderReceiver Windows application.

## Instructions for Cursor Agent

When this command is invoked, build the Windows app:

```powershell
.\scripts\build_win_app.ps1
```

Or build manually:

```powershell
cd win
cargo build --release
```

### Expected Output

The executables will be at:
- `win\build\ThunderReceiver.exe` (UI launcher)
- `win\build\thunder_receiver.exe` (CLI receiver)

### On Success

Report:
```
✅ Windows app built successfully!
   UI:  win\build\ThunderReceiver.exe
   CLI: win\build\thunder_receiver.exe
```

### On Failure

1. Show the build error
2. Attempt to fix compilation issues
3. Retry the build

