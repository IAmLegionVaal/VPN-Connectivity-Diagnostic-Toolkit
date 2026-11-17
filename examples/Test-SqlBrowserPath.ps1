#Requires -Version 5.1
<#
.SYNOPSIS
    Read-only TCP 1433 and SQL Browser UDP 1434 connectivity diagnostics.
.DESCRIPTION
    Named-instance discovery is not evidence of successful ODBC authentication.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Server,
    [ValidateRange(1,65535)][int]$TcpPort = 1433,
    [ValidateRange(1,65535)][int]$BrowserPort = 1434,
    [ValidateRange(100,10000)][int]$TimeoutMs = 2500
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    $addresses = [System.Net.Dns]::GetHostAddresses($Server) |
        ForEach-Object { $_.IPAddressToString }
    Write-Host ('DNS: {0}' -f ($addresses -join ', '))
} catch { Write-Warning ('DNS lookup: {0}' -f $_.Exception.Message) }

$tcp = New-Object System.Net.Sockets.TcpClient
$connected = $false
try {
    $async = $tcp.BeginConnect($Server, $TcpPort, $null, $null)
    try {
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            $tcp.EndConnect($async)
            $connected = $tcp.Connected
        } else { Write-Warning 'TCP connection timed out' }
    } finally {
        $async.AsyncWaitHandle.Close()
    }
} catch { Write-Warning ('TCP failed: {0}' -f $_.Exception.Message) }
finally { $tcp.Close() }
Write-Host ('TCP {0}:{1} reachable: {2}' -f $Server, $TcpPort, $connected)

$udp = New-Object System.Net.Sockets.UdpClient
try {
    $udp.Client.ReceiveTimeout = $TimeoutMs
    $udp.Connect($Server, $BrowserPort)
    [byte[]]$probe = @(0x03)
    [void]$udp.Send($probe, $probe.Length)
    $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
    $reply = $udp.Receive([ref]$endpoint)
    $decoded = [System.Text.Encoding]::ASCII.GetString($reply)
    $safe = [regex]::Replace($decoded, '[^\x20-\x7E]', ' ')
    Write-Host ('UDP SQL Browser: {0}' -f $safe.Trim())
} catch { Write-Warning ('UDP SQL Browser did not return a usable reply: {0}' -f $_.Exception.Message) }
finally { $udp.Dispose() }
Write-Host 'Next: independently test SQL TLS certificate validation and application credentials.'
