<#
.SYNOPSIS
    Build and run the Windows viewer UI (Start/Stop + logs).

.DESCRIPTION
    Builds the Windows receiver UI (`thunder_receiver_ui.exe`) and runs it.
    The UI launches the existing `thunder_receiver.exe` CLI as a child process and
    surfaces connection + stats in a small Win32 window.
#>

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$WinDir = Join-Path $ProjectDir "win"

Write-Host "========================================"
Write-Host "ThunderMirror - Windows Viewer UI"
Write-Host "========================================"
Write-Host ""

# Ensure logs directory exists
$LogsDir = Join-Path $ProjectDir "logs"
if (!(Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

# Build (release)
Write-Host "[1/2] Building..."

Push-Location $WinDir
try {
    # Temporarily allow stderr output without treating it as an error
    # (cargo outputs warnings to stderr, which PowerShell treats as errors)
    $prevErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"

    $buildOutput = cargo build --release 2>&1
    $buildExitCode = $LASTEXITCODE

    $ErrorActionPreference = $prevErrorActionPreference

    if ($buildExitCode -eq 0) {
        Write-Host "      Build successful"
    } else {
        Write-Host "      Build failed:"
        Write-Host $buildOutput
        exit 1
    }
} finally {
    Pop-Location
}

# Run UI
Write-Host ""
Write-Host "[2/2] Running..."
Write-Host ""

$Executable = Join-Path $WinDir "target\release\thunder_receiver_ui.exe"

if (Test-Path $Executable) {
    & $Executable @Args
} else {
    Write-Host "ERROR: Executable not found at $Executable"
    Write-Host ""
    Write-Host "Try building manually:"
    Write-Host "  cd win; cargo build --release"
    exit 1
}
