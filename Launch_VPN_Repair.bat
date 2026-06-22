@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0VPN_Connectivity_Repair_Toolkit.ps1' -ErrorAction SilentlyContinue"

:menu
cls
echo ============================================================
echo   VPN CONNECTIVITY REPAIR TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe repair set
echo   3. Restart VPN and IPsec services
echo   4. Reconnect an existing Windows VPN profile
echo   5. Restart a selected VPN or network adapter
echo   6. Renew DHCP on a selected adapter
echo   7. Flush DNS cache
echo   8. Reset Winsock and TCP-IP
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" goto diagnose
if "%CHOICE%"=="2" goto safe
if "%CHOICE%"=="3" goto services
if "%CHOICE%"=="4" goto reconnect
if "%CHOICE%"=="5" goto adapter
if "%CHOICE%"=="6" goto dhcp
if "%CHOICE%"=="7" goto dns
if "%CHOICE%"=="8" goto stack
if "%CHOICE%"=="0" goto end
goto menu

:diagnose
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1"
goto complete

:safe
set /p CONNECTION=VPN profile name (leave blank to skip reconnect): 
set /p ADAPTER=Adapter name (leave blank to skip adapter restart): 
if "%CONNECTION%"=="" if "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RepairAllSafe
if not "%CONNECTION%"=="" if "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RepairAllSafe -ConnectionName "%CONNECTION%"
if "%CONNECTION%"=="" if not "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RepairAllSafe -AdapterName "%ADAPTER%"
if not "%CONNECTION%"=="" if not "%ADAPTER%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RepairAllSafe -ConnectionName "%CONNECTION%" -AdapterName "%ADAPTER%"
goto complete

:services
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RestartVpnServices
goto complete

:reconnect
set /p CONNECTION=VPN profile name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -ReconnectVpn -ConnectionName "%CONNECTION%"
goto complete

:adapter
set /p ADAPTER=Adapter name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RestartVpnAdapter -AdapterName "%ADAPTER%"
goto complete

:dhcp
set /p ADAPTER=Adapter name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -RenewDhcp -AdapterName "%ADAPTER%"
goto complete

:dns
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -FlushDns
goto complete

:stack
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VPN_Connectivity_Repair_Toolkit.ps1" -ResetWinsockTcpIp
goto complete

:complete
echo.
pause
goto menu

:end
endlocal
