@echo off
setlocal

net session > nul 2>&1
if errorlevel 1 (
  echo This script must be run as Administrator.
  echo Right-click setup_server_firewall.bat and choose "Run as administrator".
  pause
  exit /b 1
)

netsh advfirewall firewall add rule name="Safety Monitor Server TCP 8000" dir=in action=allow protocol=TCP localport=8000 > nul
if errorlevel 1 (
  echo Failed to add firewall rule for TCP 8000.
  pause
  exit /b 1
)

echo Firewall rule added:
echo   Safety Monitor Server TCP 8000
echo.
echo Other PCs should be able to open:
echo   http://SERVER_PC_IP:8000/health
pause
endlocal
