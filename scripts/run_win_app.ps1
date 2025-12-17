<#
.SYNOPSIS
    Build and run the ThunderReceiver Windows app.

.DESCRIPTION
    Builds the ThunderReceiver application if needed and launches it.

.PARAMETER Rebuild
    Force a rebuild even if the executable exists.
#>

param(
    [switch]$Rebuild,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$WinDir = Join-Path $ProjectDir "win"
$BuildDir = Join-Path $WinDir "build"
$Executable = Join-Path $BuildDir "ThunderReceiver.exe"

# Build if needed
if ($Rebuild -or !(Test-Path $Executable)) {
    & "$ScriptDir\build_win_app.ps1"
    if ($LASTEXITCODE -ne 0) {
        exit 1
    }
    Write-Host ""
}

# Check if executable exists
if (!(Test-Path $Executable)) {
    Write-Host "ERROR: Executable not found. Run with -Rebuild flag."
    exit 1
}

Write-Host "Launching ThunderReceiver..."
& $Executable @Args
