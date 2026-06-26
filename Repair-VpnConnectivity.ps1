#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConnectionName,
    [switch]$Reconnect,
    [switch]$RestartRasServices,
    [switch]$ResetNetworkStack,
    [switch]$ClearDns,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = "$env:USERPROFILE\Desktop\VpnRepair"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$warnings = [System.Collections.Generic.List[string]]::new()
$logPath = $null

function Write-RepairLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN')][string]$Level = 'INFO'
    )

    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Host $entry
    if ($logPath) {
        Add-Content -LiteralPath $logPath -Value $entry -Encoding UTF8
    }
}

function Add-RepairWarning {
    param([Parameter(Mandatory)][string]$Message)

    $warnings.Add($Message)
    Write-RepairLog -Level WARN -Message $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int[]]$SuccessExitCodes = @(0)
    )

    $outputFile = Join-Path $OutputPath (($Name -replace '[^A-Za-z0-9-]', '_') + '.txt')
    & $FilePath @ArgumentList 2>&1 | Tee-Object -FilePath $outputFile
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $SuccessExitCodes) {
        throw "$Name exited with code $exitCode. Review '$outputFile'."
    }
}

try {
    if ($env:OS -ne 'Windows_NT') {
        throw 'This repair requires Windows.'
    }

    if (-not ($Reconnect -or $RestartRasServices -or $ResetNetworkStack -or $ClearDns)) {
        throw 'Choose at least one repair action.'
    }

    if (($RestartRasServices -or $ResetNetworkStack -or $ClearDns) -and -not (Test-IsAdministrator)) {
        throw 'Run PowerShell as Administrator for service, DNS, or network-stack repair actions.'
    }

    if ($Reconnect -and [string]::IsNullOrWhiteSpace($ConnectionName)) {
        throw '-ConnectionName is required when -Reconnect is selected.'
    }

    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    $logPath = Join-Path $OutputPath ('repair-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))

    $vpnConnections = @()
    if (Get-Command -Name 'Get-VpnConnection' -ErrorAction SilentlyContinue) {
        $vpnConnections += @(Get-VpnConnection -ErrorAction SilentlyContinue)
        $vpnConnections += @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)
    }
    $vpnConnections |
        Sort-Object Name, AllUserConnection -Unique |
        Export-Clixml (Join-Path $OutputPath 'vpn-before.xml')
    Invoke-NativeCommand -Name 'Rasdial Before' -FilePath 'rasdial.exe'

    if ($Reconnect -and $PSCmdlet.ShouldProcess($ConnectionName, 'Disconnect and reconnect saved VPN connection')) {
        & rasdial.exe $ConnectionName '/disconnect' 2>&1 |
            Tee-Object -FilePath (Join-Path $OutputPath 'vpn-disconnect.txt')
        $disconnectExitCode = $LASTEXITCODE
        if ($disconnectExitCode -ne 0) {
            Add-RepairWarning "VPN disconnect returned exit code $disconnectExitCode; continuing with reconnect."
        }

        Start-Sleep -Seconds 2
        Invoke-NativeCommand -Name 'VPN Reconnect' -FilePath 'rasdial.exe' -ArgumentList @($ConnectionName)
        Write-RepairLog "VPN reconnect completed for '$ConnectionName'."
    }

    if ($RestartRasServices) {
        foreach ($serviceName in 'PolicyAgent', 'IKEEXT', 'RasMan') {
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            if (-not $service) {
                Add-RepairWarning "Service '$serviceName' is unavailable."
                continue
            }

            if ($PSCmdlet.ShouldProcess($serviceName, 'Restart VPN support service')) {
                try {
                    if ($service.Status -eq 'Running') {
                        Restart-Service -Name $serviceName -Force -ErrorAction Stop
                    }
                    else {
                        Start-Service -Name $serviceName -ErrorAction Stop
                    }
                    Write-RepairLog "Started or restarted '$serviceName'."
                }
                catch {
                    Add-RepairWarning "Could not restart '$serviceName': $($_.Exception.Message)"
                }
            }
        }
    }

    if ($ClearDns -and $PSCmdlet.ShouldProcess('Windows DNS client cache', 'Flush cache')) {
        Clear-DnsClientCache -ErrorAction Stop
        Write-RepairLog 'DNS client cache was flushed.'
    }

    if ($ResetNetworkStack -and $PSCmdlet.ShouldProcess('Windows network stack', 'Reset Winsock and TCP/IP')) {
        Invoke-NativeCommand -Name 'Winsock Reset' -FilePath 'netsh.exe' -ArgumentList @('winsock', 'reset')
        Invoke-NativeCommand -Name 'TCPIP Reset' -FilePath 'netsh.exe' -ArgumentList @('int', 'ip', 'reset')
        'Restart Windows to complete the network stack reset.' |
            Set-Content -LiteralPath (Join-Path $OutputPath 'restart-required.txt') -Encoding UTF8
        Write-RepairLog 'Winsock and TCP/IP reset completed. A restart is required.'
    }

    Invoke-NativeCommand -Name 'Rasdial After' -FilePath 'rasdial.exe'
    $warnings | Set-Content -LiteralPath (Join-Path $OutputPath 'warnings.txt') -Encoding UTF8

    if ($warnings.Count -gt 0) {
        Write-RepairLog -Level WARN -Message "Completed with $($warnings.Count) warning(s)."
        exit 2
    }

    Write-RepairLog 'VPN connectivity repair workflow completed.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
