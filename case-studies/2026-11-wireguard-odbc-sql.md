# Field case: WireGuard tunnel works but SQL Server ODBC named instance fails

**Incident month:** November 2026. **Status:** Diagnostic investigation in progress; root cause and end-to-end ODBC restoration **not confirmed**.

## Evidence
A SQL Server 2022 named instance was discovered via SQL Browser on UDP 1434, advertising a TCP listener on 1433. Tests of TCP 1433 from the affected WireGuard client were initially unsuccessful and later intermittent. A 32-bit DSN using Microsoft ODBC Driver 18 was affected. This demonstrates why successful tunnel and named-instance discovery do not prove application connectivity.

## Diagnostic order
1. Confirm active WireGuard interface, allowed source/destination networks and Windows route table.
2. Compare DNS resolution and actual VPN source interface with the intended server route.
3. Query UDP 1434 for the named instance and test its advertised TCP port separately.
4. Verify server-side SQL listener and Windows Defender Firewall source restrictions.
5. After reliable TCP, troubleshoot ODBC Driver 18 TLS trust and Windows/SQL authentication using the correct 32-bit or 64-bit ODBC administrator.
6. Check machine-domain trust separately following a domain controller replacement or rejoin.

## Example commands
```powershell
Get-NetAdapter | Where-Object Name -Match 'WireGuard'
Get-NetRoute | Sort-Object RouteMetric | Select-Object -First 25
Resolve-DnsName db.example.internal
Test-NetConnection db.example.internal -Port 1433 -InformationLevel Detailed
& "$env:WINDIR\SysWOW64\odbcad32.exe"  # 32-bit ODBC Administrator
```

## Safety
Never publish VPN configs, SQL connection strings, client IPs, private keys or credentials. Do not open port 1433 to the internet or disable SQL TLS verification just to make the DSN connect.

## Completion criteria
Repeatable TCP connection from VPN address, authenticated ODBC connection and successful application test. Not verified in the source case.
