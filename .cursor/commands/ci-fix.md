# CI Fix - Check and Fix CI Errors Command

This command checks CI status, identifies failures, fixes them, and auto-commits when everything passes.

## Instructions for Cursor Agent

When this command is invoked:

### 1. Check Current Branch and PR Status

```bash
# Get current branch
git branch --show-current

# Check if there's an open PR for this branch
gh pr status

# Get CI check status
gh pr checks

# Or if no PR, check recent workflow runs
gh run list --limit 5
```

### 2. Identify CI Failures

If CI is failing, get detailed logs:

```bash
# For PR checks
gh pr checks --json name,state,conclusion

# Get failed run details
gh run view <run-id> --log-failed
```

### 3. Categorize and Fix Errors

Common CI failure categories:

#### Rust Formatting Issues
```bash
cd shared && cargo fmt --all
cd win && cargo fmt --all
```

#### Rust Clippy Warnings
```bash
cd shared && cargo clippy --all-targets --all-features -- -D warnings 2>&1
cd win && cargo clippy --all-targets --all-features -- -D warnings 2>&1
```
Fix any warnings reported.

#### Rust Build/Test Failures
```bash
cd shared && cargo build && cargo test
cd win && cargo build
```

#### Swift Build Failures
```bash
cd mac && swift build
```

#### Swift Test Failures
```bash
cd mac && swift test
```

#### Missing Files (docs validation)
Create any missing required files.

#### Shell Script Syntax Errors
```bash
for script in scripts/*.sh; do bash -n "$script"; done
```

### 4. Run Full Local CI Check

Before committing, run the complete CI check locally:

```bash
# Rust shared
cd shared
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all
cargo build --all

# Rust win
cd ../win
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
cargo build

# Swift
cd ../mac
swift build
swift test || true  # May have no tests yet

# Shell scripts
cd ..
for script in scripts/*.sh; do
    echo "Checking $script..."
    bash -n "$script"
done
```

### 5. Auto-Commit If All Checks Pass

If all local checks pass:

```bash
# Stage all changes
git add -A

# Check what changed
git status
git diff --cached --stat

# Commit with descriptive message
git commit -m "ci: fix CI errors

- <list specific fixes made>
"

# Push to trigger CI
git push origin $(git branch --show-current)
```

### 6. Wait and Verify CI Passes

```bash
# Wait for CI to complete (poll every 30 seconds)
gh run watch

# Or check status manually
gh pr checks
```

If CI still fails:
1. Get new error logs
2. Fix remaining issues
3. Repeat until green

### 7. Report Results

Print summary:
```
## CI Fix Summary

Branch: <branch-name>
PR: <pr-url if exists>

Fixes Applied:
- <fix 1>
- <fix 2>

CI Status: ✅ PASSING / ❌ STILL FAILING

<if failing, list remaining issues>
```

## Common Fixes Reference

### Rust Format
```rust
// Before (wrong)
fn foo(   x:i32)->bool{true}

// After (correct)
fn foo(x: i32) -> bool {
    true
}
```

### Clippy Common Issues
- `clippy::needless_return` - Remove explicit `return` at end of function
- `clippy::redundant_clone` - Remove unnecessary `.clone()`
- `clippy::unused_imports` - Remove unused imports
- `clippy::let_and_return` - Simplify let followed by return

### Swift Common Issues
- Missing imports
- Type mismatches
- Closure capture issues (use `[weak self]` or capture values before closure)

## Notes

- Always run local checks before pushing
- If unsure about a fix, ask the user
- Keep commits focused on CI fixes only
- Don't mix feature changes with CI fixes
- If CI fails due to environment issues (not code), note it and skip
