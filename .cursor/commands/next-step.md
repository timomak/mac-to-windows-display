# Next Step - Phase Driver Command

This command implements the next unchecked item in the development phase.

## Instructions for Cursor Agent

When this command is invoked:

### 1. Read Current Phase Status

Read `docs/PHASE.md` and determine:
- Current `PHASE` number (0-4)
- The next unchecked `[ ]` item in that phase
- If all items in current phase are complete, move to next phase

### 2. Print Plan

Before making any changes, print:
```
## Next Step Plan

Phase: <N>
Item: <item description>
Files to modify: <list of files>
Acceptance check: <how we'll verify success>
```

### 3. Implement ONE Item

Implement only the single next item. Keep changes small and reviewable.

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

### 5. Validate SSH First

Before any Windows tests, verify SSH works:
```bash
ssh blade18-tb "whoami"
```

If this fails, STOP and instruct user to re-run setup scripts.

### 6. Run Windows Tests via SSH

If the change affects Windows:
```bash
ssh blade18-tb "cd /path/to/project && powershell.exe -File scripts/check_link_win.ps1"
```

Run any phase-relevant Windows smoke tests.

### 7. On Success

If all tests pass:

1. Update `docs/PHASE.md` - check off the completed item `[x]`
2. Update "Current focus" section to next item
3. Commit with message format:
   ```
   phase <N>: <brief item summary>
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
## Next Step Plan

Phase: 1
Item: Add quinn QUIC dependency to shared crate
Files to modify: shared/Cargo.toml
Acceptance check: cargo build succeeds with quinn

---

[Implementing...]

Adding quinn = "0.10" to shared/Cargo.toml...

[Running checks...]
$ cargo fmt --check
$ cargo clippy -- -D warnings  
$ cargo test

All checks passed!

[Updating docs/PHASE.md...]
[Committing...]

$ git add shared/Cargo.toml docs/PHASE.md
$ git commit -m "phase 1: add quinn QUIC dependency"
$ git push origin main

Done! Phase 1 item completed.
```

## Notes

- Always validate SSH connectivity before remote operations
- Keep each step atomic and reversible
- If unsure about an implementation detail, ask the user
- Use SSH MCP if available, fall back to plain ssh blade18-tb commands
- Collect logs from both sides when debugging
