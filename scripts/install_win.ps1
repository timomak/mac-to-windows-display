<#
.SYNOPSIS
    Install ThunderReceiver to the user's system.

.DESCRIPTION
    Builds ThunderReceiver and installs it to the user's local AppData folder.
    Creates Start Menu and optional Desktop shortcuts.

.PARAMETER NoDesktopShortcut
    If specified, skips creating a desktop shortcut.
#>

param(
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$WinDir = Join-Path $ProjectDir "win"

# Installation paths
$AppName = "ThunderReceiver"
$InstallDir = Join-Path $env:LOCALAPPDATA $AppName
$ExePath = Join-Path $InstallDir "$AppName.exe"
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartMenuShortcut = Join-Path $StartMenuDir "$AppName.lnk"
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$AppName.lnk"

Write-Host "========================================"
Write-Host "Installing ThunderReceiver"
Write-Host "========================================"
Write-Host ""

# Build first
Write-Host "[1/4] Building..."
& "$ScriptDir\build_win_app.ps1" -OutputDir $InstallDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Build failed"
    exit 1
}

# Create Start Menu shortcut
Write-Host ""
Write-Host "[2/4] Creating Start Menu shortcut..."

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($StartMenuShortcut)
$Shortcut.TargetPath = $ExePath
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.Description = "ThunderMirror Windows Receiver"
$Shortcut.Save()
Write-Host "      Created: $StartMenuShortcut"

# Create Desktop shortcut (optional)
if (-not $NoDesktopShortcut) {
    Write-Host ""
    Write-Host "[3/4] Creating Desktop shortcut..."
    
    $Shortcut = $WshShell.CreateShortcut($DesktopShortcut)
    $Shortcut.TargetPath = $ExePath
    $Shortcut.WorkingDirectory = $InstallDir
    $Shortcut.Description = "ThunderMirror Windows Receiver"
    $Shortcut.Save()
    Write-Host "      Created: $DesktopShortcut"
} else {
    Write-Host ""
    Write-Host "[3/4] Skipping Desktop shortcut (--NoDesktopShortcut specified)"
}

# Done
Write-Host ""
Write-Host "[4/4] Verifying installation..."

if (Test-Path $ExePath) {
    Write-Host "      OK"
} else {
    Write-Host "ERROR: Installation verification failed"
    exit 1
}

Write-Host ""
Write-Host "========================================"
Write-Host "Installation complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "ThunderReceiver is now installed at:"
Write-Host "  $InstallDir"
Write-Host ""
Write-Host "You can find it in:"
Write-Host "  - Start Menu (search for 'ThunderReceiver')"
if (-not $NoDesktopShortcut) {
    Write-Host "  - Desktop shortcut"
}
Write-Host ""
Write-Host "To uninstall:"
Write-Host "  Remove-Item -Recurse '$InstallDir'"
Write-Host "  Remove-Item '$StartMenuShortcut'"
if (-not $NoDesktopShortcut) {
    Write-Host "  Remove-Item '$DesktopShortcut'"
}

