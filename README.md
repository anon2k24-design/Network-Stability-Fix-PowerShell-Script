# Network Stability Fix - PowerShell Script

PowerShell script to fix Windows network instability. Automatically clears DNS cache, resets Winsock/TCP-IP stack, renews DHCP lease, and restarts network adapters. Includes optional reboot prompt to fully apply Winsock/TCP-IP changes.

## Features

- **Automated connectivity testing** – Tests against multiple targets (Cloudflare, Google DNS, google.com)
- **DNS cache clearing** – Flushes stale DNS entries with `Clear-DnsClientCache`
- **DHCP lease renewal** – Releases and renews IP address
- **Winsock reset** – Resets Windows socket layer (`netsh winsock reset`)
- **TCP/IP reset** – Resets TCP/IP stack (`netsh int ip reset`)
- **Adapter restart** – Re-enables active network adapters
- **Optional reboot prompt** – Ask to reboot after fixes (required for Winsock/TCP-IP to fully apply)
- **Self-elevating** – Automatically requests admin privileges via UAC

## Requirements

- **Windows 10/11** (or Windows Server 2012+)
- **PowerShell 5.1+** (built into Windows)
- **Administrator privileges** (script auto-elevates if needed)

## Installation

### Option 1: Download from GitHub

1. Clone or download this repository:
   ```powershell
   cd C:\Users\YourName\Documents
   git clone https://github.com/YOUR_USERNAME/network-stability-fix.git
   ```

2. Navigate to the script folder:
   ```powershell
   cd network-stability-fix
   ```

### Option 2: Manual Download

1. Download `network-stability-fix.ps1` from the [Releases](#) page
2. Save to your Desktop or Documents folder:
