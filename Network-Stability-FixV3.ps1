# ============================================================================
# Network Stability Fix v3
# ============================================================================
# Windows PowerShell 5.1 / Windows 10-11
# Staged network repair with diagnostics, ARP flush, proxy check,
# active adapter targeting, and latency/jitter validation.
#
# Support this project:
#   PayPal: https://www.paypal.com/donate/?business=UNP6WN3E95EAL&currency_code=USD
#   GitHub: https://github.com/anon2k24-design
#   Sponsor: https://github.com/sponsors/anon2k24-design
# ============================================================================

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $CommandLine = "-ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $CommandLine
    exit
}

$ChangeLog = @()
$LatencyTargets = @(
    @{ Name = "Gateway";    Host = $null },
    @{ Name = "Cloudflare"; Host = "1.1.1.1" },
    @{ Name = "GoogleDNS";  Host = "8.8.8.8" }
)

function Add-Change {
    param($Type, $Path, $Name, $OldValue, $NewValue)
    $script:ChangeLog += [PSCustomObject]@{
        Timestamp = Get-Date
        Type      = $Type
        Path      = $Path
        Name      = $Name
        OldValue  = $OldValue
        NewValue  = $NewValue
    }
    try {
        $script:ChangeLog | Export-Csv ".\network-stability-fix-log.csv" -NoTypeInformation -Encoding UTF8
    } catch {}
}

function Get-ActiveRouteInfo {
    try {
        $route = Get-NetRoute -DestinationPrefix "0.0.0.0/0" |
            Where-Object { $_.NextHop -and $_.State -ne "Unreachable" } |
            Sort-Object RouteMetric, InterfaceMetric |
            Select-Object -First 1

        if (-not $route) { return $null }

        $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        $ipCfg   = Get-NetIPConfiguration -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue

        [PSCustomObject]@{
            InterfaceIndex = $route.InterfaceIndex
            AdapterName    = $adapter.Name
            InterfaceAlias = $ipCfg.InterfaceAlias
            NextHop        = $route.NextHop
            IPv4Address    = if ($ipCfg.IPv4Address) { $ipCfg.IPv4Address.IPAddress } else { $null }
            DhcpEnabled    = if ($ipCfg.NetIPv4Interface) { $ipCfg.NetIPv4Interface.Dhcp } else { $null }
            InterfaceDesc  = $adapter.InterfaceDescription
        }
    } catch {
        return $null
    }
}

function Test-NetworkStage {
    param(
        [string]$Gateway,
        [string]$PublicIP = "1.1.1.1",
        [string]$Hostname = "google.com"
    )

    $gatewayOk = $false
    $publicOk  = $false
    $dnsOk     = $false

    if ($Gateway) {
        try { $gatewayOk = Test-Connection -ComputerName $Gateway -Count 2 -Quiet -ErrorAction SilentlyContinue } catch {}
    }

    try { $publicOk = Test-Connection -ComputerName $PublicIP -Count 2 -Quiet -ErrorAction SilentlyContinue } catch {}
    try { $dnsOk    = Test-Connection -ComputerName $Hostname -Count 2 -Quiet -ErrorAction SilentlyContinue } catch {}

    [PSCustomObject]@{
        GatewayTarget = $Gateway
        GatewayOK     = $gatewayOk
        PublicTarget  = $PublicIP
        PublicOK      = $publicOk
        HostTarget    = $Hostname
        HostOK        = $dnsOk
    }
}

function Show-TestResults {
    param($Result)

    Write-Host ""
    Write-Host "Connectivity Test Results" -ForegroundColor Cyan
    Write-Host "  Gateway ($($Result.GatewayTarget)) : $($Result.GatewayOK)" -ForegroundColor White
    Write-Host "  Public IP ($($Result.PublicTarget)) : $($Result.PublicOK)" -ForegroundColor White
    Write-Host "  Hostname ($($Result.HostTarget)) : $($Result.HostOK)" -ForegroundColor White

    if (-not $Result.GatewayOK -and $Result.PublicOK -and $Result.HostOK) {
        Write-Host "  Note: Gateway may block ICMP but internet still works." -ForegroundColor DarkYellow
    }
    elseif ($Result.GatewayOK -and -not $Result.PublicOK) {
        Write-Host "  Likely issue: internet path beyond router/modem." -ForegroundColor DarkYellow
    }
    elseif ($Result.PublicOK -and -not $Result.HostOK) {
        Write-Host "  Likely issue: DNS resolution." -ForegroundColor DarkYellow
    }
    elseif (-not $Result.GatewayOK -and -not $Result.PublicOK -and -not $Result.HostOK) {
        Write-Host "  Likely issue: adapter, DHCP, gateway, or full stack problem." -ForegroundColor DarkYellow
    }
}

function Test-NetworkHealthy {
    param($Result)
    if ($Result.PublicOK -and $Result.HostOK) { return $true }
    return $false
}

function Show-WinHttpProxy {
    Write-Host ""
    Write-Host "WinHTTP Proxy Status" -ForegroundColor Cyan
    try {
        $proxyOutput = netsh winhttp show proxy
        $proxyOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Add-Change -Type "Diagnostics" -Path "WinHTTP" -Name "ProxyStatus" -OldValue "" -NewValue (($proxyOutput | Out-String).Trim())
    } catch {
        Write-Host "  Could not read WinHTTP proxy status." -ForegroundColor DarkYellow
    }
}

function Repair-DnsOnly {
    Write-Host ""
    Write-Host "[Stage 1] Flushing DNS and reregistering DNS..." -ForegroundColor Yellow
    try {
        Clear-DnsClientCache
        Add-Change -Type "Repair" -Path "DNS" -Name "Cache" -OldValue "Unknown" -NewValue "Flushed"
        Write-Host "  DNS cache flushed" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to flush DNS cache" -ForegroundColor DarkYellow
    }

    try {
        ipconfig /registerdns | Out-Null
        Add-Change -Type "Repair" -Path "DNS" -Name "RegisterDNS" -OldValue "Unknown" -NewValue "Triggered"
        Write-Host "  DNS re-registration triggered" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to trigger DNS registration" -ForegroundColor DarkYellow
    }
}

function Repair-ClearArp {
    Write-Host ""
    Write-Host "[Optional] Clearing ARP cache..." -ForegroundColor Yellow
    try {
        netsh interface ip delete arpcache | Out-Null
        Add-Change -Type "Repair" -Path "ARP" -Name "Cache" -OldValue "Unknown" -NewValue "Flushed"
        Write-Host "  ARP cache cleared" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to clear ARP cache" -ForegroundColor DarkYellow
    }
}

function Repair-DhcpRenew {
    param($RouteInfo)

    Write-Host ""
    Write-Host "[Stage 2] DHCP renew on active adapter..." -ForegroundColor Yellow

    if (-not $RouteInfo) {
        Write-Host "  No active route info found. Skipping DHCP renew." -ForegroundColor DarkYellow
        return
    }

    if ($RouteInfo.DhcpEnabled -ne "Enabled") {
        Write-Host "  Active adapter does not appear to use DHCP. Skipping renew." -ForegroundColor DarkYellow
        return
    }

    try {
        ipconfig /release | Out-Null
        Start-Sleep -Seconds 2
        ipconfig /renew | Out-Null
        Add-Change -Type "Repair" -Path $RouteInfo.AdapterName -Name "DHCP" -OldValue "Lease Present" -NewValue "Released/Renewed"
        Write-Host "  DHCP lease released and renewed" -ForegroundColor Green
    } catch {
        Write-Host "  DHCP renew failed" -ForegroundColor DarkYellow
    }
}

function Repair-RestartAdapter {
    param($RouteInfo)

    Write-Host ""
    Write-Host "[Stage 3] Restarting active adapter..." -ForegroundColor Yellow

    if (-not $RouteInfo -or -not $RouteInfo.AdapterName) {
        Write-Host "  No active adapter found. Skipping adapter restart." -ForegroundColor DarkYellow
        return
    }

    try {
        Restart-NetAdapter -Name $RouteInfo.AdapterName -Confirm:$false -ErrorAction Stop
        Add-Change -Type "Repair" -Path $RouteInfo.AdapterName -Name "AdapterRestart" -OldValue "Up" -NewValue "Restarted"
        Write-Host "  Restarted adapter: $($RouteInfo.AdapterName)" -ForegroundColor Green
        Start-Sleep -Seconds 8
    } catch {
        Write-Host "  Restart-NetAdapter failed for $($RouteInfo.AdapterName)" -ForegroundColor DarkYellow
    }
}

function Repair-FullReset {
    Write-Host ""
    Write-Host "[Stage 4] Full network stack reset..." -ForegroundColor Yellow
    Write-Host "  This requires a reboot." -ForegroundColor DarkYellow

    try {
        netsh winsock reset | Out-Null
        Add-Change -Type "Repair" -Path "Winsock" -Name "Reset" -OldValue "Current Catalog" -NewValue "Reset Requested"
        Write-Host "  Winsock reset queued" -ForegroundColor Green
    } catch {
        Write-Host "  Winsock reset failed" -ForegroundColor DarkYellow
    }

    try {
        netsh int ip reset | Out-Null
        Add-Change -Type "Repair" -Path "TCP/IP" -Name "Reset" -OldValue "Current Stack" -NewValue "Reset Requested"
        Write-Host "  TCP/IP reset queued" -ForegroundColor Green
    } catch {
        Write-Host "  TCP/IP reset failed" -ForegroundColor DarkYellow
    }
}

function Get-LatencyStats {
    param(
        [string]$Target,
        [string]$Name,
        [int]$Count = 10
    )

    $samples = @()

    for ($i = 1; $i -le $Count; $i++) {
        try {
            $r = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop
            $lat = [double]$r.ResponseTime
            $samples += $lat
        } catch {}
        Start-Sleep -Milliseconds 300
    }

    if ($samples.Count -eq 0) {
        return [PSCustomObject]@{
            Name      = $Name
            Target    = $Target
            Success   = 0
            MinMs     = $null
            AvgMs     = $null
            MaxMs     = $null
            JitterMs  = $null
        }
    }

    $min = ($samples | Measure-Object -Minimum).Minimum
    $avg = [math]::Round(($samples | Measure-Object -Average).Average, 2)
    $max = ($samples | Measure-Object -Maximum).Maximum

    $jitter = $null
    if ($samples.Count -gt 1) {
        $diffs = @()
        for ($i = 1; $i -lt $samples.Count; $i++) {
            $diffs += [math]::Abs($samples[$i] - $samples[$i - 1])
        }
        $jitter = [math]::Round(($diffs | Measure-Object -Average).Average, 2)
    }

    [PSCustomObject]@{
        Name      = $Name
        Target    = $Target
        Success   = $samples.Count
        MinMs     = $min
        AvgMs     = $avg
        MaxMs     = $max
        JitterMs  = $jitter
    }
}

function Run-LatencyValidation {
    param($RouteInfo)

    Write-Host ""
    Write-Host "Post-Repair Latency Validation" -ForegroundColor Cyan
    Write-Host "  Running 10 pings each..." -ForegroundColor White

    $results = @()
    foreach ($t in $script:LatencyTargets) {
        $targetHost = $t.Host
        if (-not $targetHost -and $RouteInfo.NextHop) {
            $targetHost = $RouteInfo.NextHop
        }

        if ($targetHost) {
            $stats = Get-LatencyStats -Target $targetHost -Name $t.Name -Count 10
            $results += $stats
        }
    }

    foreach ($row in $results) {
        Write-Host ("  {0} ({1}) -> Success={2} Min={3} Avg={4} Max={5} Jitter={6}" -f `
            $row.Name, $row.Target, $row.Success, $row.MinMs, $row.AvgMs, $row.MaxMs, $row.JitterMs) -ForegroundColor Green
    }

    try {
        $results | Export-Csv ".\network-latency-validation.csv" -NoTypeInformation -Encoding UTF8
    } catch {}

    return $results
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Network Stability Fix v3" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Support this project:" -ForegroundColor Magenta
Write-Host "  PayPal: https://www.paypal.com/donate/?business=UNP6WN3E95EAL&currency_code=USD" -ForegroundColor White
Write-Host "  GitHub: https://github.com/anon2k24-design" -ForegroundColor White
Write-Host "  Sponsor: https://github.com/sponsors/anon2k24-design" -ForegroundColor White
Write-Host ""

$routeInfo = Get-ActiveRouteInfo
if (-not $routeInfo) {
    Write-Host "Could not determine active default route or adapter." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Active adapter: $($routeInfo.AdapterName)" -ForegroundColor Green
Write-Host "Description: $($routeInfo.InterfaceDesc)" -ForegroundColor Green
Write-Host "Gateway: $($routeInfo.NextHop)" -ForegroundColor Green
Write-Host "IPv4: $($routeInfo.IPv4Address)" -ForegroundColor Green
Write-Host "DHCP: $($routeInfo.DhcpEnabled)" -ForegroundColor Green

Show-WinHttpProxy

$initial = Test-NetworkStage -Gateway $routeInfo.NextHop
Show-TestResults -Result $initial

if (Test-NetworkHealthy -Result $initial) {
    Write-Host ""
    Write-Host "Network appears functional. Running validation only..." -ForegroundColor Green
    Run-LatencyValidation -RouteInfo $routeInfo | Out-Null
    Write-Host "Logs saved to: network-stability-fix-log.csv and network-latency-validation.csv" -ForegroundColor White
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Host ""
Write-Host "Select repair mode:" -ForegroundColor Yellow
Write-Host "  1. Safe     (DNS only)" -ForegroundColor White
Write-Host "  2. Standard (DNS + DHCP renew + adapter restart)" -ForegroundColor White
Write-Host "  3. Full     (Standard + ARP clear + Winsock/TCP reset)" -ForegroundColor White
$mode = Read-Host "Enter choice (1-3)"

Repair-DnsOnly
Start-Sleep -Seconds 3
$afterDns = Test-NetworkStage -Gateway $routeInfo.NextHop
Show-TestResults -Result $afterDns

if (Test-NetworkHealthy -Result $afterDns) {
    Write-Host ""
    Write-Host "Connectivity restored after Stage 1." -ForegroundColor Green
    Run-LatencyValidation -RouteInfo $routeInfo | Out-Null
    Write-Host "Logs saved to: network-stability-fix-log.csv and network-latency-validation.csv" -ForegroundColor White
    Read-Host "Press Enter to exit"
    exit 0
}

if ($mode -eq "2" -or $mode -eq "3") {
    Repair-DhcpRenew -RouteInfo $routeInfo
    Start-Sleep -Seconds 5
    $afterDhcp = Test-NetworkStage -Gateway $routeInfo.NextHop
    Show-TestResults -Result $afterDhcp

    if (Test-NetworkHealthy -Result $afterDhcp) {
        Write-Host ""
        Write-Host "Connectivity restored after DHCP renew." -ForegroundColor Green
        Run-LatencyValidation -RouteInfo $routeInfo | Out-Null
        Write-Host "Logs saved to: network-stability-fix-log.csv and network-latency-validation.csv" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit 0
    }

    Repair-RestartAdapter -RouteInfo $routeInfo
    $routeInfo = Get-ActiveRouteInfo
    $afterAdapter = Test-NetworkStage -Gateway $routeInfo.NextHop
    Show-TestResults -Result $afterAdapter

    if (Test-NetworkHealthy -Result $afterAdapter) {
        Write-Host ""
        Write-Host "Connectivity restored after adapter restart." -ForegroundColor Green
        Run-LatencyValidation -RouteInfo $routeInfo | Out-Null
        Write-Host "Logs saved to: network-stability-fix-log.csv and network-latency-validation.csv" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit 0
    }
}

$needsReboot = $false

if ($mode -eq "3") {
    Repair-ClearArp
    Start-Sleep -Seconds 2

    Repair-FullReset
    $needsReboot = $true
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  REPAIR SEQUENCE COMPLETE" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log saved to: network-stability-fix-log.csv" -ForegroundColor White
Write-Host "Latency file: network-latency-validation.csv (generated when validation runs)" -ForegroundColor White

if ($needsReboot) {
    Write-Host "A reboot is required to complete Winsock/TCP reset." -ForegroundColor Yellow
    $R = Read-Host "Reboot now? (Y/N)"
    if ($R -match '^[Yy]') {
        Restart-Computer -Force
    }
} else {
    Write-Host "If the issue persists, rerun and choose Full mode." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
}