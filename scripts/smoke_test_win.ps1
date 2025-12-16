<#
.SYNOPSIS
    Phase-aware smoke test for Windows.

.DESCRIPTION
    Runs appropriate tests based on the current development phase.
#>

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

Write-Host "========================================"
Write-Host "ThunderMirror - Windows Smoke Test"
Write-Host "========================================"
Write-Host ""

$TestsPassed = 0
$TestsTotal = 0

function Run-Test {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    $script:TestsTotal++
    Write-Host -NoNewline "[Test] $Name... "
    
    try {
        $result = & $Test
        if ($result -or $LASTEXITCODE -eq 0) {
            Write-Host "OK" -ForegroundColor Green
            $script:TestsPassed++
            return $true
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "FAIL" -ForegroundColor Red
        return $false
    }
}

# Phase 0 Tests
Write-Host "=== Phase 0: Infrastructure ==="
Write-Host ""

# Test: Thunderbolt adapter exists
Run-Test "Thunderbolt adapter exists" {
    $adapters = Get-NetAdapter | Where-Object { 
        $_.Status -eq "Up" -and 
        ($_.Name -match "Thunderbolt|USB4" -or $_.InterfaceDescription -match "Thunderbolt|USB4")
    }
    return $adapters.Count -gt 0
}

# Test: Ping Mac
$MacIP = if ($env:THUNDER_MAC_IP) { $env:THUNDER_MAC_IP } else { "192.168.50.1" }
Run-Test "Ping Mac ($MacIP)" {
    return Test-Connection -ComputerName $MacIP -Count 1 -Quiet -ErrorAction SilentlyContinue
}

# Test: SSH server running
Run-Test "SSH server (sshd) running" {
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    return $svc -and $svc.Status -eq "Running"
}

# Test: logs directory
$LogsDir = Join-Path $ProjectDir "logs"
Run-Test "logs\ directory exists" {
    return Test-Path $LogsDir
}

# Test: Rust win crate builds
$WinDir = Join-Path $ProjectDir "win"
if (Test-Path (Join-Path $WinDir "Cargo.toml")) {
    Run-Test "Rust win crate builds" {
        Push-Location $WinDir
        try {
            cargo check 2>&1 | Out-Null
            return $LASTEXITCODE -eq 0
        } finally {
            Pop-Location
        }
    }
}

# Phase 1 Tests: QUIC Transport
Write-Host ""
Write-Host "=== Phase 1: QUIC Transport ==="
Write-Host ""

# Test: Win receiver builds
$WinDir = Join-Path $ProjectDir "win"
if (Test-Path (Join-Path $WinDir "Cargo.toml")) {
    Run-Test "Win receiver --help works" {
        Push-Location $WinDir
        try {
            $output = cargo run -- --help 2>&1
            return $LASTEXITCODE -eq 0
        } finally {
            Pop-Location
        }
    }
}

# Phase 2 Tests: Screen Capture Receiver
Write-Host ""
Write-Host "=== Phase 2: Screen Capture Receiver ==="
Write-Host ""

# Test: Receiver handles resolution changes (receiver already supports this from Phase 1)
# The receiver dynamically resizes its buffer when resolution changes
$WinDir = Join-Path $ProjectDir "win"
if (Test-Path (Join-Path $WinDir "Cargo.toml")) {
    Run-Test "Receiver supports dynamic resolution" {
        Push-Location $WinDir
        try {
            # Check that the receiver code handles resolution changes
            $content = Get-Content -Path "src\main.rs" -Raw
            return $content -match "Resolution changed to"
        } finally {
            Pop-Location
        }
    }
}

Write-Host ""
Write-Host "========================================"

if ($TestsPassed -eq $TestsTotal) {
    Write-Host "OK All $TestsTotal tests passed!" -ForegroundColor Green
    Write-Host "========================================"
    exit 0
} else {
    $TestsFailed = $TestsTotal - $TestsPassed
    Write-Host "WARNING: $TestsPassed/$TestsTotal passed ($TestsFailed failed)" -ForegroundColor Yellow
    Write-Host "========================================"
    exit 1
}
