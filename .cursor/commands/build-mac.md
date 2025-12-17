# Build Mac App

Build the ThunderMirror macOS application.

## Instructions for Cursor Agent

When this command is invoked, build the Mac app:

```bash
cd mac && swift build -c release
```

Or use the build script for a full app bundle:

```bash
./scripts/build_mac_app.sh
```

### Expected Output

The app bundle will be at `mac/build/ThunderMirror.app`.

### On Success

Report:
```
✅ Mac app built successfully!
   Location: mac/build/ThunderMirror.app
```

### On Failure

1. Show the build error
2. Attempt to fix compilation issues
3. Retry the build

