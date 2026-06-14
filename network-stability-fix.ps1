# ============================================================================
# Network Stability Fix - PowerShell Script
# ============================================================================
# Windows network stability fix. Clears DNS, resets Winsock/TCP-IP, renews DHCP.
#
# Support this project:
#   PayPal: https://www.paypal.com/donate/?business=UNP6WN3E95EAL&currency_code=USD
#   GitHub: https://github.com/anon2k24-design
# ============================================================================

if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`""
    Start-Process PowerShell.exe -Verb Runas -ArgumentList $CommandLine
    Exit
}

$Targets = @("1.1.1.1", "8.8.8.8", "google.com")
$ActiveAdapters = Get-NetAdapter | Where-Object Status -eq "Up"

if (-not $ActiveAdapters) {
    Write-Host "No active adapter." -ForegroundColor Red
    exit 1
}

Write-Host "Testing connectivity..." -ForegroundColor Cyan
$Failed = $false

foreach ($T in $Targets) {
    $Ok = Test-Connection -ComputerName $T -Count 2 -Quiet
    Write-Host "$T : $Ok"
    if (-not $Ok) { $Failed = $true }
}

if (-not $Failed) {
    Write-Host "Network healthy. No fixes needed." -ForegroundColor Green
    exit 0
}

Write-Host "Applying repairs..." -ForegroundColor Yellow
Clear-DnsClientCache
ipconfig /registerdns | Out-Null
ipconfig /release | Out-Null
Start-Sleep -Seconds 2
ipconfig /renew | Out-Null
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null
foreach ($A in $ActiveAdapters) { Restart-NetAdapter -Name $A.Name -Confirm:$false -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 10

Write-Host "Reboot recommended." -ForegroundColor Yellow
$R = Read-Host "Reboot now? (Y/N)"
if ($R -match '^[Yy]') { Restart-Computer -Force }