<#
.SYNOPSIS
    Verify Thunderbolt/USB4 network link on Windows.

.DESCRIPTION
    This script checks for a Thunderbolt or USB4 network adapter, displays its IP,
    and pings the Mac to verify connectivity.

.PARAMETER MacIP
    IP address of the Mac. Default: 192.168.50.1 or $env:THUNDER_MAC_IP

.EXAMPLE
    .\scripts\check_link_win.ps1
    .\scripts\check_link_win.ps1 -MacIP 192.168.50.1
#>

param(
    [string]$MacIP = $null
)

# Configuration
if (-not $MacIP) {
    $MacIP = if ($env:THUNDER_MAC_IP) { $env:THUNDER_MAC_IP } else { "192.168.50.1" }
}

Write-Host "========================================"
Write-Host "ThunderMirror - Windows Link Check"
Write-Host "========================================"
Write-Host ""

# Step 1: Find Thunderbolt/USB4 network adapter
Write-Host "[1/3] Looking for Thunderbolt/USB4 network adapter..."

$tbAdapter = $null
$tbIP = $null

# Look for adapters with Thunderbolt or USB4 in the name
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }

foreach ($adapter in $adapters) {
    $name = $adapter.Name
    $desc = $adapter.InterfaceDescription
    
    if ($name -match "Thunderbolt|USB4|Thunder" -or $desc -match "Thunderbolt|USB4") {
        $tbAdapter = $adapter
        break
    }
}

# If not found by name, look for our expected IP range
if (-not $tbAdapter) {
    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ipConfig -and $ipConfig.IPAddress -match "^192\.168\.50\.") {
            $tbAdapter = $adapter
            $tbIP = $ipConfig.IPAddress
            break
        }
    }
}

# Still not found? List all adapters for user to identify
if (-not $tbAdapter) {
    Write-Host "      FAIL: No Thunderbolt/USB4 adapter found" -ForegroundColor Red
    Write-Host ""
    Write-Host "      Available network adapters:"
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = (Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
        Write-Host "        - $($_.Name): $ip ($($_.InterfaceDescription))"
    }
    Write-Host ""
    Write-Host "      Possible causes:"
    Write-Host "      - Thunderbolt cable not connected"
    Write-Host "      - Need to authorize connection in Thunderbolt Control Center"
    Write-Host "      - Driver not installed"
    Write-Host ""
    Write-Host "      Try:"
    Write-Host "      1. Check Device Manager for Thunderbolt controller"
    Write-Host "      2. Open Intel/vendor Thunderbolt software and authorize"
    Write-Host "      3. See docs/SETUP_THUNDERBOLT_BRIDGE.md"
    exit 1
}

Write-Host "      OK: Found adapter '$($tbAdapter.Name)'" -ForegroundColor Green

# Step 2: Get IP address
Write-Host ""
Write-Host "[2/3] Checking IP address..."

if (-not $tbIP) {
    $ipConfig = Get-NetIPAddress -InterfaceIndex $tbAdapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    if ($ipConfig) {
        $tbIP = $ipConfig.IPAddress
    }
}

if (-not $tbIP) {
    Write-Host "      FAIL: No IPv4 address on $($tbAdapter.Name)" -ForegroundColor Red
    Write-Host ""
    Write-Host "      The adapter exists but has no IP. Try:"
    Write-Host "      1. Settings -> Network -> $($tbAdapter.Name) -> Edit IP assignment"
    Write-Host "      2. Set to Manual, IP: 192.168.50.2, Subnet: 255.255.255.0"
    Write-Host ""
    Write-Host "      Or run (Admin PowerShell):"
    Write-Host "      New-NetIPAddress -InterfaceIndex $($tbAdapter.ifIndex) -IPAddress 192.168.50.2 -PrefixLength 24"
    exit 1
}

Write-Host "      OK: IP address is $tbIP" -ForegroundColor Green

# Step 3: Ping Mac
Write-Host ""
Write-Host "[3/3] Pinging Mac at $MacIP..."

$pingResult = Test-Connection -ComputerName $MacIP -Count 3 -Quiet -ErrorAction SilentlyContinue

if ($pingResult) {
    $pingDetail = Test-Connection -ComputerName $MacIP -Count 1 -ErrorAction SilentlyContinue
    $latency = $pingDetail.ResponseTime
    Write-Host "      OK: Ping successful (${latency}ms)" -ForegroundColor Green
} else {
    Write-Host "      FAIL: Cannot ping $MacIP" -ForegroundColor Red
    Write-Host ""
    Write-Host "      Possible causes:"
    Write-Host "      - Mac doesn't have IP $MacIP"
    Write-Host "      - macOS firewall blocking ICMP"
    Write-Host "      - Different subnet"
    Write-Host ""
    Write-Host "      Try:"
    Write-Host "      1. On Mac, run: ifconfig | grep 192.168"
    Write-Host "      2. Ensure Mac has IP in 192.168.50.x subnet"
    Write-Host ""
    Write-Host "      If Mac IP is different, run:"
    Write-Host "      .\scripts\check_link_win.ps1 -MacIP <correct_mac_ip>"
    exit 1
}

# Summary
Write-Host ""
Write-Host "========================================"
Write-Host "OK Thunderbolt link is working!" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
Write-Host "Adapter:    $($tbAdapter.Name)"
Write-Host "Windows IP: $tbIP"
Write-Host "Mac IP:     $MacIP"
Write-Host ""
Write-Host "Next step: Run SSH setup (if not done)"
Write-Host "  Windows: .\scripts\01_setup_ssh_win.ps1"
Write-Host "  Mac:     ./scripts/01_setup_ssh_mac.sh"
