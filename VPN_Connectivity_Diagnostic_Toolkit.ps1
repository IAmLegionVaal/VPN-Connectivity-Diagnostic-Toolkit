#requires -Version 5.1
<#
.SYNOPSIS
    Connectivity Diagnostic Toolkit.
.DESCRIPTION
    Read-only Windows network context reporter for support review.
#>
[CmdletBinding()]
param([string]$TargetHost='www.microsoft.com',[string]$OutputPath)

$RunStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Connectivity_Reports' }
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
function New-Check { param($Category,$Name,$Status,$Value,$Recommendation) [PSCustomObject]@{Category=$Category;Name=$Name;Status=$Status;Value=$Value;Recommendation=$Recommendation} }
$checks = @()
Get-NetAdapter | Select-Object Name,Status,LinkSpeed,InterfaceDescription | Export-Csv (Join-Path $OutputPath "adapters_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
Get-NetRoute | Select-Object DestinationPrefix,NextHop,InterfaceAlias,RouteMetric | Export-Csv (Join-Path $OutputPath "routes_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv4DefaultGateway,DNSServer | Export-Csv (Join-Path $OutputPath "ip_config_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
foreach($hostName in @($TargetHost,'www.microsoft.com','login.microsoftonline.com') | Select-Object -Unique){
    try { [void][System.Net.Dns]::GetHostAddresses($hostName); $dns='Resolved' } catch { $dns='DNS failed' }
    try { $tcp = Test-NetConnection -ComputerName $hostName -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch { $tcp=$false }
    $checks += New-Check 'Connectivity' $hostName ($(if($tcp){'OK'}else{'Warning'})) "DNS=$dns; TCP443=$tcp" 'Review DNS, route, firewall, or access path if this fails.'
}
$checks | Export-Csv (Join-Path $OutputPath "connectivity_checks_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$checks | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputPath "connectivity_checks_$RunStamp.json") -Encoding UTF8
$checks | ConvertTo-Html -Title 'Connectivity Diagnostic' -PreContent "<h1>Connectivity Diagnostic - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p>" | Set-Content (Join-Path $OutputPath "connectivity_report_$RunStamp.html") -Encoding UTF8
$checks | Format-Table -AutoSize -Wrap
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
