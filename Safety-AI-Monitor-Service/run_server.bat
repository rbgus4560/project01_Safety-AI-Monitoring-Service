@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "SERVER_DIR=%ROOT_DIR%\safety_monitor_server"
set "PYTHON_CMD=%ROOT_DIR%\.venv\Scripts\python.exe"
set "SERVER_LOG_DIR=%ROOT_DIR%\logs"
set "SAFETY_MONITOR_LOG_FILE=%SERVER_LOG_DIR%\server.log"

call :check_workspace_path
if errorlevel 1 goto :fail
if not exist "%SERVER_LOG_DIR%" mkdir "%SERVER_LOG_DIR%"

call "%ROOT_DIR%\install_dependencies.bat" server
if errorlevel 1 goto :fail

if not exist "%PYTHON_CMD%" (
  echo Python venv not found:
  echo   %PYTHON_CMD%
  goto :fail
)
if not exist "%SERVER_DIR%\main.py" (
  echo Server entry file not found:
  echo   %SERVER_DIR%\main.py
  goto :fail
)

echo Starting Safety Monitor Server on http://0.0.0.0:8000
echo Server log file: %SAFETY_MONITOR_LOG_FILE%
echo.
echo Server URLs to use from other PCs:
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Sort-Object InterfaceAlias | ForEach-Object { Write-Host ('  http://' + $_.IPAddress + ':8000') }"
echo.
echo If other PCs cannot open http://SERVER_IP:8000/health, run setup_server_firewall.bat as Administrator on this server PC.
echo.
pushd "%SERVER_DIR%"
"%PYTHON_CMD%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --no-access-log
popd
pause
exit /b 0

:check_workspace_path
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "'%ROOT_DIR%'.Length"`) do set "ROOT_LEN=%%i"
if %ROOT_LEN% GEQ 80 (
  echo Workspace path is too long for stable builds/runs:
  echo   %ROOT_DIR%
  echo Move the repository near C:\ or D:\ root.
  exit /b 1
)
exit /b 0

:fail
echo Server run failed.
pause
exit /b 1
