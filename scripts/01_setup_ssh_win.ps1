<#
.SYNOPSIS
    Set up OpenSSH Server on Windows for ThunderMirror.

.DESCRIPTION
    This script:
    1. Requires Admin/elevated PowerShell
    2. Detects Thunderbolt/USB4 network adapter
    3. Optionally sets a static IP
    4. Installs/enables OpenSSH Server
    5. Opens Windows Firewall for SSH

.PARAMETER StaticIP
    Static IP to set. Default: 192.168.50.2

.PARAMETER SkipStaticIP
    Skip static IP configuration

.EXAMPLE
    # Run as Administrator
    .\scripts\01_setup_ssh_win.ps1
#>

param(
    [string]$StaticIP = "192.168.50.2",
    [switch]$SkipStaticIP
)

# Check for Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "========================================"
    Write-Host "ERROR: This script requires Administrator privileges" -ForegroundColor Red
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator:"
    Write-Host "1. Right-click PowerShell"
    Write-Host "2. Select 'Run as administrator'"
    Write-Host "3. Navigate to project folder"
    Write-Host "4. Run: .\scripts\01_setup_ssh_win.ps1"
    exit 1
}

Write-Host "========================================"
Write-Host "ThunderMirror - Windows SSH Setup"
Write-Host "========================================"
Write-Host ""

# Step 1: Find Thunderbolt adapter
Write-Host "[1/5] Detecting Thunderbolt/USB4 network adapter..."

$tbAdapter = $null
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

foreach ($adapter in $adapters) {
    $name = $adapter.Name
    $desc = $adapter.InterfaceDescription
    
    if ($name -match "Thunderbolt|USB4|Thunder" -or $desc -match "Thunderbolt|USB4") {
        $tbAdapter = $adapter
        break
    }
}

# If not found by name, try to find by IP range or guess
if (-not $tbAdapter) {
    # Look for adapter with 192.168.50.x
    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipConfig -and $ipConfig.IPAddress -match "^192\.168\.50\.") {
            $tbAdapter = $adapter
            break
        }
    }
}

if (-not $tbAdapter) {
    Write-Host "      WARNING: Could not auto-detect Thunderbolt adapter" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "      Available adapters:"
    $adapters | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        Write-Host "        [$($_.ifIndex)] $($_.Name): $ip"
    }
    Write-Host ""
    $adapterIndex = Read-Host "      Enter the interface index of your Thunderbolt adapter"
    $tbAdapter = Get-NetAdapter -InterfaceIndex ([int]$adapterIndex) -ErrorAction SilentlyContinue
    
    if (-not $tbAdapter) {
        Write-Host "      FAIL: Invalid adapter index" -ForegroundColor Red
        exit 1
    }
}

$currentIP = (Get-NetIPAddress -InterfaceIndex $tbAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
Write-Host "      OK: Found adapter '$($tbAdapter.Name)'" -ForegroundColor Green
if ($currentIP) {
    Write-Host "      Current IP: $currentIP"
}

# Step 2: Set static IP (optional)
Write-Host ""
Write-Host "[2/5] Static IP configuration..."

if ($SkipStaticIP) {
    Write-Host "      Skipping static IP (--SkipStaticIP flag)"
} elseif ($currentIP -eq $StaticIP) {
    Write-Host "      OK: Already has static IP $StaticIP" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "      Recommended: Set static IP $StaticIP for reliable connection"
    $setIP = Read-Host "      Set static IP $StaticIP? (Y/n)"
    
    if ($setIP -ne "n" -and $setIP -ne "N") {
        Write-Host "      Setting static IP..."
        
        # Remove existing IP config
        Get-NetIPAddress -InterfaceIndex $tbAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceIndex $tbAdapter.ifIndex -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        
        # Set new static IP
        try {
            New-NetIPAddress -InterfaceIndex $tbAdapter.ifIndex -IPAddress $StaticIP -PrefixLength 24 -ErrorAction Stop | Out-Null
            Write-Host "      OK: Static IP set to $StaticIP" -ForegroundColor Green
            $currentIP = $StaticIP
        } catch {
            Write-Host "      WARNING: Failed to set static IP: $_" -ForegroundColor Yellow
            Write-Host "      You may need to set it manually in Network Settings"
        }
    } else {
        Write-Host "      Skipped static IP configuration"
    }
}

# Step 3: Install OpenSSH Server
Write-Host ""
Write-Host "[3/5] Installing OpenSSH Server..."

$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

if ($sshCapability.State -eq "Installed") {
    Write-Host "      OK: OpenSSH Server already installed" -ForegroundColor Green
} else {
    Write-Host "      Installing OpenSSH Server (this may take a minute)..."
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop | Out-Null
        Write-Host "      OK: OpenSSH Server installed" -ForegroundColor Green
    } catch {
        Write-Host "      FAIL: Could not install OpenSSH Server" -ForegroundColor Red
        Write-Host "      Error: $_"
        Write-Host ""
        Write-Host "      Try manual installation:"
        Write-Host "      1. Settings -> Apps -> Optional Features -> Add a feature"
        Write-Host "      2. Search for 'OpenSSH Server'"
        Write-Host "      3. Install"
        exit 1
    }
}

# Step 4: Start and enable sshd service
Write-Host ""
Write-Host "[4/5] Configuring sshd service..."

try {
    # Set to auto-start
    Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
    Write-Host "      OK: sshd set to auto-start" -ForegroundColor Green
    
    # Start the service
    $sshService = Get-Service -Name sshd
    if ($sshService.Status -ne "Running") {
        Start-Service sshd -ErrorAction Stop
        Write-Host "      OK: sshd service started" -ForegroundColor Green
    } else {
        Write-Host "      OK: sshd service already running" -ForegroundColor Green
    }
} catch {
    Write-Host "      FAIL: Could not configure sshd service" -ForegroundColor Red
    Write-Host "      Error: $_"
    Write-Host ""
    Write-Host "      Try manually:"
    Write-Host "      1. Open Services (services.msc)"
    Write-Host "      2. Find 'OpenSSH SSH Server'"
    Write-Host "      3. Set Startup Type to 'Automatic'"
    Write-Host "      4. Click Start"
    exit 1
}

# Step 5: Configure firewall
Write-Host ""
Write-Host "[5/5] Configuring Windows Firewall..."

$firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

if ($firewallRule) {
    if ($firewallRule.Enabled -eq "True") {
        Write-Host "      OK: Firewall rule already exists and enabled" -ForegroundColor Green
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
        Write-Host "      OK: Firewall rule enabled" -ForegroundColor Green
    }
} else {
    try {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH SSH Server (ThunderMirror)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction Stop | Out-Null
        Write-Host "      OK: Firewall rule created" -ForegroundColor Green
    } catch {
        Write-Host "      WARNING: Could not create firewall rule" -ForegroundColor Yellow
        Write-Host "      SSH may be blocked. You may need to add the rule manually."
    }
}

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "OK SSH Server setup complete!" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
Write-Host "Windows Thunderbolt IP: $currentIP"
Write-Host "SSH Port: 22"
Write-Host "Username: $env:USERNAME"
Write-Host ""
Write-Host "Next step: On Mac, run:"
Write-Host "  ./scripts/01_setup_ssh_mac.sh"
Write-Host ""
Write-Host "When prompted, use:"
Write-Host "  Windows IP: $currentIP"
Write-Host "  Username:   $env:USERNAME"
