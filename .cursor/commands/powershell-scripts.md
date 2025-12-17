# PowerShell Script Guidelines for Windows

## Why We Generate `.ps1` Files

On Windows, running commands like `cargo run` often fails because:
1. **PATH issues**: Rust/Cargo may not be in the current shell's PATH
2. **Environment setup**: Tools need environment variables set (e.g., `$env:USERPROFILE\.cargo\bin`)
3. **PowerShell syntax**: `&&` doesn't work in older PowerShell; use `;` instead
4. **Execution policy**: Scripts need `-ExecutionPolicy Bypass` to run

Creating a `.ps1` script centralizes this setup and makes it repeatable.

## When to Generate a New `.ps1` Script

Generate a new script when:
- Running a multi-step build/run command that needs environment setup
- The command fails due to PATH or environment issues
- You need a repeatable way to launch something (dev server, build, test runner)

## Script Template

```powershell
# Description of what this script does
$env:Path = "$env:USERPROFILE\.cargo\bin;$env:Path"

Set-Location -Path $PSScriptRoot
# your commands here
```

## How to Run

```powershell
powershell -ExecutionPolicy Bypass -File "path\to\script.ps1"
```

## When to Keep vs Commit

### ✅ COMMIT these scripts:
- `run.ps1` / `dev.ps1` - Standard dev workflow scripts in project subdirs
- Scripts that fix environment/PATH issues others will hit
- Scripts referenced in README or docs

### ❌ DON'T COMMIT:
- Temporary one-off scripts (e.g., `temp_*.ps1`)
- Scripts with hardcoded user paths or credentials
- Scripts generated just to debug a one-time issue

### 📁 Where to Put Them:
- Project-specific: `win/run.ps1`, `mac/run.sh`
- Cross-cutting: `scripts/` folder
- Temporary: Delete after use, or add to `.gitignore`

## Existing Scripts in This Repo

| Script | Purpose | Commit? |
|--------|---------|---------|
| `win/run.ps1` | Run thunder_receiver_ui with Cargo PATH | ✅ Yes |
| `scripts/run_win_app.ps1` | Run Windows app | ✅ Yes |
| `scripts/run_win.ps1` | Run Windows CLI | ✅ Yes |

