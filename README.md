# Network Stability Fix - PowerShell Script

PowerShell script to fix Windows network instability. Automatically clears DNS cache, resets Winsock/TCP-IP stack, renews DHCP lease, and restarts network adapters. Includes optional reboot prompt.

## Support This Project

If this script helped you, consider supporting:

- **💰 PayPal**: https://www.paypal.com/donate/?business=UNP6WN3E95EAL&currency_code=USD
- **🌟 GitHub**: https://github.com/anon2k24-design

---

## Features

- Automated connectivity testing
- DNS cache clearing (`Clear-DnsClientCache`)
- DHCP lease renewal (`ipconfig /release` + `/renew`)
- Winsock reset (`netsh winsock reset`)
- TCP/IP reset (`netsh int ip reset`)
- Adapter restart (`Restart-NetAdapter`)
- Optional reboot prompt
- Self-elevating (auto-requests admin)

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator privileges

## How to Run

### Method 1: PowerShell as Admin

1. Open PowerShell as Administrator
2. Navigate to script:
   ```powershell
   cd C:\Users\YourName\Desktop
   ```
3. Run:
   ```powershell
   .\network-stability-fix.ps1
   ```

If execution policy blocks it:
```powershell
PowerShell -ExecutionPolicy Bypass -File .\network-stability-fix.ps1
```

### Method 2: Right-Click → Run with PowerShell

1. Right-click `network-stability-fix.ps1`
2. Choose **Run with PowerShell**
3. Click **Yes** on UAC prompt

### Method 3: Desktop Shortcut

1. Desktop → New → Shortcut
2. Location:
   ```text
   powershell.exe -NoExit -ExecutionPolicy Bypass -File "C:\Users\YourName\Desktop\network-stability-fix.ps1"
   ```
3. Name: `Network Stability Fix`
4. Properties → Advanced → **Run as administrator**

## What It Does

| Step | Action | Applies Immediately? |
|------|--------|----------------------|
| 1 | Clear DNS cache | ✅ Yes |
| 2 | Re-register DNS | ✅ Yes |
| 3 | Release IP | ✅ Yes |
| 4 | Renew IP | ✅ Yes |
| 5 | Reset Winsock | ⚠️ Requires reboot |
| 6 | Reset TCP/IP | ⚠️ Requires reboot |
| 7 | Restart adapters | ✅ Yes |

**Reboot required** after Winsock/TCP-IP reset for full effect.

## Customizing Targets

Edit `$Targets` at the top:
```powershell
$Targets = @("1.1.1.1", "8.8.8.8", "your-router-ip")
```

## Troubleshooting

### Scripts disabled error
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### No adapter found
- Check Ethernet/WiFi is connected
- Ensure adapter status is "Up"

### No UAC prompt
- Run PowerShell as Admin manually first
- Ensure UAC is enabled in Windows

## License

MIT License

## Support

- **💰 PayPal**: https://www.paypal.com/donate/?business=UNP6WN3E95EAL&currency_code=USD
- **🌟 GitHub**: https://github.com/anon2k24-design
