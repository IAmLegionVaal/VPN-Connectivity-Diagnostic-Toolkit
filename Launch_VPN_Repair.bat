@echo off
setlocal
cd /d "%~dp0"

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

if "%CHOICE%"=="1" set ARGS=&goto run
if "%CHOICE%"=="2" goto safe
if "%CHOICE%"=="3" set ARGS=-RestartVpnServices&goto run
if "%CHOICE%"=="4" goto reconnect
if "%CHOICE%"=="5" goto adapter
if "%CHOICE%"=="6" goto dhcp
if "%CHOICE%"=="7" set ARGS=-FlushDns&goto run
if "%CHOICE%"=="8" set ARGS=-ResetWinsockTcpIp&goto run
if "%CHOICE%"=="0" goto end
goto menu

:safe
set /p CONNECTION=VPN profile name (leave blank to skip reconnect): 
set /p ADAPTER=Adapter name (leave blank to skip adapter restart): 
set ARGS=-RepairAllSafe
if not "%CONNECTION%"=="" set ARGS=%ARGS% -ConnectionName "%CONNECTION%"
if not "%ADAPTER%"=="" set ARGS=%ARGS% -AdapterName "%ADAPTER%"
goto run

:reconnect
set /p CONNECTION=VPN profile name: 
set ARGS=-ReconnectVpn -ConnectionName "%CONNECTION%"
goto run

:adapter
set /p ADAPTER=Adapter name: 
set ARGS=-RestartVpnAdapter -AdapterName "%ADAPTER%"
goto run

:dhcp
set /p ADAPTER=Adapter name: 
set ARGS=-RenewDhcp -AdapterName "%ADAPTER%"
goto run

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0VPN_Connectivity_Repair_Toolkit.ps1' -ErrorAction SilentlyContinue; & '%~dp0VPN_Connectivity_Repair_Toolkit.ps1' %ARGS%"
echo.
pause
goto menu

:end
endlocal
