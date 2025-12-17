<#
.SYNOPSIS
    Build and run the Windows receiver.

.DESCRIPTION
    This script builds and runs the ThunderMirror Windows receiver.

.PARAMETER Args
    Arguments to pass to the receiver executable.

.EXAMPLE
    .\scripts\run_win.ps1
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
Write-Host "ThunderMirror - Windows Receiver"
Write-Host "========================================"
Write-Host ""

# Ensure logs directory exists
$LogsDir = Join-Path $ProjectDir "logs"
if (!(Test-Path $LogsDir)) {
    New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
}

# Build
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

# Run
Write-Host ""
Write-Host "[2/2] Running..."
Write-Host ""

$Executable = Join-Path $WinDir "target\release\thunder_receiver.exe"

if (Test-Path $Executable) {
    & $Executable @Args
} else {
    Write-Host "ERROR: Executable not found at $Executable"
    Write-Host ""
    Write-Host "This is a scaffold. Full implementation coming in Phase 1+."
    exit 1
}
