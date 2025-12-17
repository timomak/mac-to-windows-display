# Next Step - Phase Driver Command

This command implements all unchecked items in the current development phase.

## Instructions for Cursor Agent

When this command is invoked:

### 1. Read Current Phase Status

Read `docs/PHASE.md` and determine:
- Current `PHASE` number (0-5)
- All unchecked `[ ]` items in that phase
- If all items in current phase are complete, move to next phase

**Note:** For Phase 3.5 (UI), use `ui-step.md` command instead.
**Note:** For Phase 5 (Performance), use `perf-step.md` command instead.

### 2. Print Plan

Before making any changes, print:
```
## Phase Completion Plan

Phase: <N>
Items to complete: <list of all unchecked items>
Files to modify: <list of all files that will be changed>
Acceptance checks: <how we'll verify success for each item>
```

### 3. Implement ALL Items in Phase

Implement all unchecked items in the current phase. Work through them systematically, but complete the entire phase before committing.

### 4. Run Local Checks

Depending on what changed:

**If shared/ changed:**
```bash
cd shared && cargo fmt --check && cargo clippy -- -D warnings && cargo test
```

**If mac/ changed:**
```bash
cd mac && swift build
```

**If win/ changed:**
```bash
cd win && cargo fmt --check && cargo clippy -- -D warnings
```

### 5. Validate Connectivity (Prefer MCP)

Before any Windows tests, verify connectivity to Windows works. Prefer using the MCP SSH tools first (they surface better errors inside Cursor), and fall back to plain `ssh` if MCP isn’t connected.

**MCP (preferred):**
- Use `blade18-tb` MCP tools:
  - `checkConnectivity(hostAlias="blade18-tb")`
  - `runRemoteCommand(hostAlias="blade18-tb", command="whoami")`

**SSH fallback:**
```bash
ssh blade18-tb "whoami"
```

If this fails, STOP and instruct user to re-run setup scripts.

### 6. Run Windows Tests (Prefer MCP)

If the change affects Windows:

**MCP (preferred):**
- `runRemoteCommand(hostAlias="blade18-tb", command="cd /path/to/project && powershell.exe -File scripts/check_link_win.ps1")`

**SSH fallback:**
```bash
ssh blade18-tb "cd /path/to/project && powershell.exe -File scripts/check_link_win.ps1"
```

Run any phase-relevant Windows smoke tests.

### 7. On Success

If all tests pass:

1. Update `docs/PHASE.md` - check off all completed items `[x]` in the phase
2. Update "Current focus" section to next phase (if phase is complete) or next item
3. Commit with message format:
   ```
   phase <N>: complete phase <N>
   ```
4. Push to origin:
   ```bash
   git push origin $(git branch --show-current)
   ```
5. If push fails due to auth, print the exact command user needs to run

### 8. On Failure

If any test fails:

1. Do NOT commit
2. Print a "Fix Plan" section explaining:
   - What failed
   - Likely cause
   - Suggested fix
3. Ensure no background processes are left running
4. Stop and wait for user to address the issue

## Example Run

```
## Phase Completion Plan

Phase: 1
Items to complete:
  - Add quinn QUIC dependency to shared crate
  - Add tokio async runtime dependency
  - Create basic QUIC client structure
Files to modify: shared/Cargo.toml, shared/src/transport.rs
Acceptance checks:
  - cargo build succeeds with quinn and tokio
  - QUIC client structure compiles

---

[Implementing...]

[Item 1/3] Adding quinn = "0.10" to shared/Cargo.toml...
[Item 2/3] Adding tokio = { version = "1", features = ["full"] }...
[Item 3/3] Creating QUIC client structure in transport.rs...

[Running checks...]
$ cargo fmt --check
$ cargo clippy -- -D warnings  
$ cargo test

All checks passed!

[Updating docs/PHASE.md...]
[Committing...]

$ git add shared/Cargo.toml shared/src/transport.rs docs/PHASE.md
$ git commit -m "phase 1: complete phase 1"
$ git push origin main

Done! Phase 1 completed.
```

## Notes

- Always validate SSH connectivity before remote operations
- Complete all items in a phase before committing
- If unsure about an implementation detail, ask the user
- Prefer SSH MCP tools (`blade18-tb`, `mac-tb`) for testing/debugging; fall back to plain `ssh blade18-tb` / `ssh mac-tb` commands if MCP isn’t connected
- Collect logs from both sides when debugging
- If a phase has many items, you may want to run checks after each major item, but only commit once at the end

## SSH Between Machines

Bidirectional SSH is configured:

| From | To | SSH Command | MCP Server |
|------|----|-------------|------------|
| Mac | Windows | `ssh blade18-tb` | `blade18-tb` |
| Windows | Mac | `ssh mac-tb` | `mac-tb` |

**Mac agent can run Windows commands:**
```bash
ssh blade18-tb "powershell.exe -Command Get-Date"
```

**Windows agent can run Mac commands:**
```bash
ssh mac-tb "uname -a"
```

Both MCP servers are configured in `.cursor/mcp.json` - after fetching latest code, restart Cursor to pick up the config.
