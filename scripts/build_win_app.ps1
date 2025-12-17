<#
.SYNOPSIS
    Build ThunderReceiver.exe - the Windows receiver application.

.DESCRIPTION
    Builds the ThunderReceiver Windows application as a release executable.
    The built .exe can be double-clicked to launch the receiver.

.PARAMETER OutputDir
    Optional output directory for the built executable. Defaults to win/build/.
#>

param(
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$WinDir = Join-Path $ProjectDir "win"
$DefaultBuildDir = Join-Path $WinDir "build"

if ($OutputDir -eq "") {
    $OutputDir = $DefaultBuildDir
}

Write-Host "========================================"
Write-Host "Building ThunderReceiver.exe"
Write-Host "========================================"
Write-Host ""

# Ensure output directory exists
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Build the release executables (both UI wrapper and CLI receiver)
Write-Host "[1/4] Building Rust project (release)..."
Write-Host ""

Push-Location $WinDir
try {
    # Run cargo build for both binaries
    $env:CARGO_TERM_COLOR = "always"
    cargo build --release --bin ThunderReceiver --bin thunder_receiver
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Build failed with exit code $LASTEXITCODE"
        exit 1
    }
    
    Write-Host ""
    Write-Host "      Build successful"
} finally {
    Pop-Location
}

# Copy executables to output directory
Write-Host ""
Write-Host "[2/4] Copying UI executable..."

$SourceExe = Join-Path $WinDir "target\release\ThunderReceiver.exe"
$DestExe = Join-Path $OutputDir "ThunderReceiver.exe"

if (Test-Path $SourceExe) {
    Copy-Item -Path $SourceExe -Destination $DestExe -Force
    Write-Host "      Copied to: $DestExe"
} else {
    Write-Host "ERROR: Built UI executable not found at $SourceExe"
    exit 1
}

# Copy the CLI receiver (required by the UI wrapper)
Write-Host ""
Write-Host "[3/4] Copying CLI receiver..."

$SourceCliExe = Join-Path $WinDir "target\release\thunder_receiver.exe"
$DestCliExe = Join-Path $OutputDir "thunder_receiver.exe"

if (Test-Path $SourceCliExe) {
    Copy-Item -Path $SourceCliExe -Destination $DestCliExe -Force
    Write-Host "      Copied to: $DestCliExe"
} else {
    Write-Host "ERROR: Built CLI executable not found at $SourceCliExe"
    exit 1
}

# Verify the executables
Write-Host ""
Write-Host "[4/4] Verifying..."

if ((Test-Path $DestExe) -and (Test-Path $DestCliExe)) {
    $uiInfo = Get-Item $DestExe
    $cliInfo = Get-Item $DestCliExe
    $uiSizeMB = [math]::Round($uiInfo.Length / 1MB, 2)
    $cliSizeMB = [math]::Round($cliInfo.Length / 1MB, 2)
    Write-Host "      ThunderReceiver.exe (UI): $uiSizeMB MB"
    Write-Host "      thunder_receiver.exe (CLI): $cliSizeMB MB"
    Write-Host "      OK"
} else {
    Write-Host "ERROR: Verification failed"
    exit 1
}

Write-Host ""
Write-Host "========================================"
Write-Host "Build complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "Files:"
Write-Host "  UI:  $DestExe"
Write-Host "  CLI: $DestCliExe"
Write-Host ""
Write-Host "To run:"
Write-Host "  & `"$DestExe`""
Write-Host ""
Write-Host "NOTE: Both files must be kept together in the same directory."
Write-Host ""
Write-Host "To create a desktop shortcut:"
Write-Host "  Right-click ThunderReceiver.exe -> Send to -> Desktop (create shortcut)"
Write-Host ""
Write-Host "To add to Start Menu:"
Write-Host "  Copy BOTH files to: $env:APPDATA\Microsoft\Windows\Start Menu\Programs\"

