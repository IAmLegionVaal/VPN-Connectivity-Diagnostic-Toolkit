#requires -Version 5.1
<#
.SYNOPSIS
    Guarded Windows VPN connectivity repair toolkit.
.DESCRIPTION
    Repairs selected local Windows VPN, adapter, service and network-stack problems.
    Diagnosis is the default. Repairs require explicit switches, confirmation and
    administrator rights where applicable.
.NOTES
    Created by Dewald Pretorius - L2 IT Support Engineer.
#>

[CmdletBinding()]
param(
    [switch]$RepairAllSafe,
    [switch]$RestartVpnServices,
    [switch]$RestartVpnAdapter,
    [switch]$ReconnectVpn,
    [switch]$FlushDns,
    [switch]$RenewDhcp,
    [switch]$ResetWinsockTcpIp,
    [string]$ConnectionName,
    [string]$AdapterName,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RebootRequired = $false
$ExitCode = 0

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) "VPN_Connectivity_Repair_$Stamp"
}
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
$LogPath = Join-Path $OutputPath 'repair.log'
$BackupPath = Join-Path $OutputPath 'backup'
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DRYRUN')][string]$Level = 'INFO'
    )
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    switch ($Level) {
        'WARN'    { Write-Host $Message -ForegroundColor Yellow }
        'ERROR'   { Write-Host $Message -ForegroundColor Red }
        'SUCCESS' { Write-Host $Message -ForegroundColor Green }
        'DRYRUN'  { Write-Host "DRY RUN: $Message" -ForegroundColor Cyan }
        default   { Write-Host $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Message,
        [switch]$HighImpact
    )
    if ($DryRun -or $Yes) { return $true }
    $token = if ($HighImpact) { 'REPAIR' } else { 'YES' }
    return (Read-Host "$Message Type $token to continue") -eq $token
}

function Require-Administrator {
    if (-not (Test-IsAdministrator)) {
        throw 'This repair requires an elevated PowerShell session.'
    }
}

function Get-SelectedVpnConnection {
    if ([string]::IsNullOrWhiteSpace($ConnectionName)) {
        throw 'Specify -ConnectionName for this action.'
    }

    $connection = Get-VpnConnection -Name $ConnectionName -ErrorAction SilentlyContinue
    if (-not $connection) {
        $connection = Get-VpnConnection -Name $ConnectionName -AllUserConnection -ErrorAction SilentlyContinue
    }
    if (-not $connection) {
        throw "VPN connection '$ConnectionName' was not found."
    }
    return $connection
}

function Get-SelectedAdapter {
    if ([string]::IsNullOrWhiteSpace($AdapterName)) {
        throw 'Specify -AdapterName for this action.'
    }
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $adapter) {
        throw "Network adapter '$AdapterName' was not found."
    }
    return $adapter
}

function Save-State {
    param([Parameter(Mandatory)][string]$Stage)

    $currentUserVpn = @()
    $allUserVpn = @()
    try { $currentUserVpn = @(Get-VpnConnection -ErrorAction Stop) } catch {}
    try { $allUserVpn = @(Get-VpnConnection -AllUserConnection -ErrorAction Stop) } catch {}

    $state = [ordered]@{
        Stage = $Stage
        Generated = (Get-Date).ToString('o')
        ScriptVersion = $ScriptVersion
        Computer = $env:COMPUTERNAME
        User = "$env:USERDOMAIN\$env:USERNAME"
        IsAdministrator = (Test-IsAdministrator)
        RequestedConnection = $ConnectionName
        RequestedAdapter = $AdapterName
        CurrentUserVpnConnections = @($currentUserVpn | Select-Object Name, ServerAddress, TunnelType, EncryptionLevel, AuthenticationMethod, ConnectionStatus, SplitTunneling, RememberCredential)
        AllUserVpnConnections = @($allUserVpn | Select-Object Name, ServerAddress, TunnelType, EncryptionLevel, AuthenticationMethod, ConnectionStatus, SplitTunneling, RememberCredential)
        Services = @(Get-Service RasMan, IKEEXT, PolicyAgent -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType)
        Adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed, ifIndex)
        IpConfiguration = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DNSServer)
        Routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object InterfaceAlias, InterfaceIndex, DestinationPrefix, NextHop, RouteMetric, Protocol, State)
    }

    $statePath = Join-Path $OutputPath "$Stage.json"
    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Log "Saved $Stage state to $statePath." 'SUCCESS'
}

function Save-Backups {
    try {
        Get-VpnConnection -ErrorAction SilentlyContinue |
            Select-Object * |
            Export-Clixml -LiteralPath (Join-Path $BackupPath 'current-user-vpn-connections.clixml')
    } catch {
        Write-Log "Could not export current-user VPN connections: $($_.Exception.Message)" 'WARN'
    }

    try {
        Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue |
            Select-Object * |
            Export-Clixml -LiteralPath (Join-Path $BackupPath 'all-user-vpn-connections.clixml')
    } catch {
        Write-Log "Could not export all-user VPN connections: $($_.Exception.Message)" 'WARN'
    }

    Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Export-Csv -LiteralPath (Join-Path $BackupPath 'ipv4-routes.csv') -NoTypeInformation -Encoding UTF8
}

function Invoke-RestartVpnServices {
    Require-Administrator
    if (-not (Confirm-Action 'Restart the Windows VPN and IPsec services?')) { throw 'User cancelled.' }

    foreach ($serviceName in @('PolicyAgent','IKEEXT','RasMan')) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "Service $serviceName was not found." 'WARN'
            continue
        }

        if ($DryRun) {
            Write-Log "Would start or restart $serviceName." 'DRYRUN'
            continue
        }

        if ($service.Status -eq 'Running') {
            Restart-Service -Name $serviceName -Force -ErrorAction Stop
        } else {
            Start-Service -Name $serviceName -ErrorAction Stop
        }
        Write-Log "Service $serviceName is running." 'SUCCESS'
    }
}

function Invoke-RestartVpnAdapter {
    Require-Administrator
    $adapter = Get-SelectedAdapter
    if (-not (Confirm-Action "Restart adapter '$AdapterName'? Connectivity will be interrupted.")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would restart adapter '$AdapterName'." 'DRYRUN'
        return
    }

    Restart-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
    Start-Sleep -Seconds 4
    $after = Get-NetAdapter -Name $adapter.Name -ErrorAction Stop
    if ($after.Status -eq 'Disabled') { throw "Adapter '$AdapterName' remained disabled." }
    Write-Log "Restarted adapter '$AdapterName'. Current status: $($after.Status)." 'SUCCESS'
}

function Invoke-ReconnectVpn {
    [void](Get-SelectedVpnConnection)
    if (-not (Confirm-Action "Disconnect and reconnect VPN '$ConnectionName' using its saved credentials?")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would disconnect and reconnect VPN '$ConnectionName'." 'DRYRUN'
        return
    }

    & rasdial.exe $ConnectionName /disconnect 2>&1 | Add-Content -LiteralPath $LogPath
    & rasdial.exe $ConnectionName 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) {
        throw "rasdial could not reconnect '$ConnectionName'. The profile may require interactive credentials or a vendor client."
    }

    Start-Sleep -Seconds 3
    $status = (Get-SelectedVpnConnection).ConnectionStatus
    if ($status -ne 'Connected') { throw "VPN '$ConnectionName' did not report Connected after repair." }
    Write-Log "VPN '$ConnectionName' reconnected successfully." 'SUCCESS'
}

function Invoke-FlushDns {
    if (-not (Confirm-Action 'Flush the Windows DNS resolver cache?')) { throw 'User cancelled.' }
    if ($DryRun) {
        Write-Log 'Would flush the DNS resolver cache.' 'DRYRUN'
        return
    }

    if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
        Clear-DnsClientCache
    } else {
        & ipconfig.exe /flushdns | Out-Null
    }
    Write-Log 'DNS resolver cache flushed.' 'SUCCESS'
}

function Invoke-RenewDhcp {
    Require-Administrator
    [void](Get-SelectedAdapter)
    if (-not (Confirm-Action "Release and renew DHCP for adapter '$AdapterName'? Connectivity will be interrupted.")) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log "Would release and renew DHCP for '$AdapterName'." 'DRYRUN'
        return
    }

    & ipconfig.exe /release "$AdapterName" 2>&1 | Add-Content -LiteralPath $LogPath
    & ipconfig.exe /renew "$AdapterName" 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw "DHCP renewal failed for '$AdapterName'." }
    Write-Log "DHCP lease renewed for '$AdapterName'." 'SUCCESS'
}

function Invoke-ResetNetworkStack {
    Require-Administrator
    if (-not (Confirm-Action 'Reset Winsock and TCP/IP? A restart is required.' -HighImpact)) { throw 'User cancelled.' }

    if ($DryRun) {
        Write-Log 'Would reset Winsock and TCP/IP. A restart would be required.' 'DRYRUN'
        return
    }

    $ipResetLog = Join-Path $OutputPath 'netsh-ip-reset.log'
    & netsh.exe winsock reset 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw 'Winsock reset failed.' }
    & netsh.exe int ip reset $ipResetLog 2>&1 | Add-Content -LiteralPath $LogPath
    if ($LASTEXITCODE -ne 0) { throw 'TCP/IP reset failed.' }
    $script:RebootRequired = $true
    Write-Log 'Winsock and TCP/IP were reset. Restart Windows before final validation.' 'SUCCESS'
}

function Invoke-SafeRepairSet {
    Invoke-RestartVpnServices
    Invoke-FlushDns
    if (-not [string]::IsNullOrWhiteSpace($AdapterName)) { Invoke-RestartVpnAdapter }
    if (-not [string]::IsNullOrWhiteSpace($ConnectionName)) { Invoke-ReconnectVpn }
}

if (-not (Get-Command Get-VpnConnection -ErrorAction SilentlyContinue)) {
    Write-Log 'The Windows VPN PowerShell module is unavailable on this system.' 'ERROR'
    exit 3
}

Write-Log "VPN Connectivity Repair Toolkit $ScriptVersion started. DryRun=$DryRun"
Save-State -Stage 'before'
Save-Backups

$hasRepair = $RepairAllSafe -or $RestartVpnServices -or $RestartVpnAdapter -or $ReconnectVpn -or $FlushDns -or $RenewDhcp -or $ResetWinsockTcpIp
if (-not $hasRepair) {
    Write-Log 'Diagnostic-only run completed. No repair switch was selected.' 'SUCCESS'
    Save-State -Stage 'after'
    exit 0
}

try {
    if ($RepairAllSafe)       { Invoke-SafeRepairSet }
    if ($RestartVpnServices)  { Invoke-RestartVpnServices }
    if ($RestartVpnAdapter)   { Invoke-RestartVpnAdapter }
    if ($ReconnectVpn)        { Invoke-ReconnectVpn }
    if ($FlushDns)            { Invoke-FlushDns }
    if ($RenewDhcp)           { Invoke-RenewDhcp }
    if ($ResetWinsockTcpIp)   { Invoke-ResetNetworkStack }
} catch {
    if ($_.Exception.Message -eq 'User cancelled.') {
        $ExitCode = 10
        Write-Log 'Repair cancelled by the user.' 'WARN'
    } elseif ($_.Exception.Message -match 'elevated') {
        $ExitCode = 4
        Write-Log $_.Exception.Message 'ERROR'
    } else {
        $ExitCode = 20
        Write-Log $_.Exception.Message 'ERROR'
    }
} finally {
    try { Save-State -Stage 'after' } catch { Write-Log "Post-repair snapshot failed: $($_.Exception.Message)" 'WARN' }
}

if ($RebootRequired) {
    Write-Log 'REBOOT REQUIRED: the network stack reset is not complete until Windows restarts.' 'WARN'
}
Write-Log "Completed with exit code $ExitCode. Output: $OutputPath" $(if ($ExitCode -eq 0) { 'SUCCESS' } else { 'ERROR' })
exit $ExitCode
