# VPN Connectivity Diagnostic and Repair Toolkit

PowerShell tooling for Windows VPN connectivity reporting and guarded local repair, created by **Dewald Pretorius**.

## Files

- `VPN_Connectivity_Diagnostic_Toolkit.ps1` — read-only adapter, IP, DNS, route and TCP connectivity reporting.
- `VPN_Connectivity_Repair_Toolkit.ps1` — guarded VPN, service, adapter, DHCP and network-stack repairs.
- `Launch_VPN_Repair.bat` — interactive technician menu.

## Repair actions

### Diagnostic default

Running the repair script without a repair switch produces before-and-after JSON state without changing the workstation.

```powershell
.\VPN_Connectivity_Repair_Toolkit.ps1
```

### Safe repair set

The safe set:

1. Starts or restarts `PolicyAgent`, `IKEEXT` and `RasMan`.
2. Flushes the DNS resolver cache.
3. Restarts one selected adapter when `-AdapterName` is supplied.
4. Reconnects one existing Windows VPN profile when `-ConnectionName` is supplied.

```powershell
.\VPN_Connectivity_Repair_Toolkit.ps1 -RepairAllSafe `
  -ConnectionName "Company VPN" -AdapterName "Wi-Fi" -DryRun
```

### Individual repairs

```powershell
.\VPN_Connectivity_Repair_Toolkit.ps1 -RestartVpnServices
.\VPN_Connectivity_Repair_Toolkit.ps1 -ReconnectVpn -ConnectionName "Company VPN"
.\VPN_Connectivity_Repair_Toolkit.ps1 -RestartVpnAdapter -AdapterName "My VPN Adapter"
.\VPN_Connectivity_Repair_Toolkit.ps1 -RenewDhcp -AdapterName "Wi-Fi"
.\VPN_Connectivity_Repair_Toolkit.ps1 -FlushDns
.\VPN_Connectivity_Repair_Toolkit.ps1 -ResetWinsockTcpIp
```

## What the repairs do

- Start or restart the Windows Remote Access and IPsec services.
- Restart one explicitly selected adapter.
- Disconnect and reconnect one existing Windows VPN profile using stored credentials.
- Release and renew DHCP on one explicitly selected adapter.
- Flush the Windows DNS cache.
- Reset Winsock and TCP/IP as a high-impact recovery action.

The tool does not create, delete or rewrite VPN profiles. It does not add routes, remove routes, change authentication methods or store credentials.

## Logs, evidence and backups

Each run creates a timestamped folder on the desktop containing:

- `before.json` and `after.json`
- `repair.log`
- Current-user and all-user VPN profile metadata exports where available
- IPv4 route backup
- Network-stack reset log when selected

## Safety

- Diagnosis is the default.
- `-DryRun` previews repair actions.
- Standard changes require typing `YES` unless `-Yes` is supplied.
- Winsock/TCP-IP reset requires typing `REPAIR` and requires a Windows restart.
- Service, adapter, DHCP and stack repairs normally require elevation.
- Reconnect works only for native Windows VPN profiles and may fail when credentials are not stored or when a vendor VPN client controls the connection.
- Adapter, DHCP and VPN restart actions can interrupt remote-support sessions.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Completed successfully, including diagnosis or dry-run |
| 3 | Required Windows VPN PowerShell support unavailable |
| 4 | Elevation required |
| 10 | User cancelled |
| 20 | Repair action failed |

## Interactive launcher

Double-click:

```text
Launch_VPN_Repair.bat
```

## Validation status

Tested successfully by the author on his own Windows machines. The documented native Windows VPN, adapter, DHCP, DNS and network-stack workflows worked as intended on those systems.

Results may vary with the Windows build, VPN profile type, authentication method, saved credentials, adapter driver, vendor VPN software, firewall policy, network configuration and user-specific environment. Use `-DryRun` before applying repairs on a new machine or VPN setup.
