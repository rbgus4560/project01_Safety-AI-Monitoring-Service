@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "VIEWER_DIR=%ROOT_DIR%\safety_monitor_viewer"
set "VIEWER_BUILD_DIR=%VIEWER_DIR%\build\windows\x64\runner\Release"
set "VIEWER_EXE=%VIEWER_BUILD_DIR%\safety_monitor_viewer.exe"
set "CONFIG_PATH=%VIEWER_DIR%\server_config.json"

call :check_workspace_path
if errorlevel 1 goto :fail
if not exist "%VIEWER_DIR%\pubspec.yaml" (
  echo Viewer project not found:
  echo   %VIEWER_DIR%\pubspec.yaml
  goto :fail
)

call :ensure_viewer_build
if errorlevel 1 goto :fail

set "DEFAULT_SERVER_URL=http://127.0.0.1:8000"
set "SERVER_URL="
if exist "%CONFIG_PATH%" (
  for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$p='%CONFIG_PATH%'; try { $json=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; if($json.api_base_url){ $json.api_base_url } } catch {}"`) do set "SERVER_URL=%%i"
)
if not defined SERVER_URL set "SERVER_URL=%DEFAULT_SERVER_URL%"

echo Current API server: %SERVER_URL%
set /p "INPUT_SERVER_URL=Enter API server URL (press Enter to keep current): "
if not "%INPUT_SERVER_URL%"=="" set "SERVER_URL=%INPUT_SERVER_URL%"

> "%CONFIG_PATH%" echo {
>> "%CONFIG_PATH%" echo   "api_base_url": "%SERVER_URL%"
>> "%CONFIG_PATH%" echo }

echo Checking server health at %SERVER_URL% ...
powershell -NoProfile -Command "try { $u='%SERVER_URL%'.TrimEnd('/') + '/health'; $r=Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 5; if($r.StatusCode -eq 200){ Write-Host 'Server health check succeeded.'; exit 0 } exit 1 } catch { Write-Host ('Server health check error: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 echo Warning: server health check failed. The viewer will still start.

start "Safety Monitor Viewer" /D "%VIEWER_BUILD_DIR%" "%VIEWER_EXE%"
exit /b 0

:ensure_viewer_build
set "NEED_BUILD=0"
if not exist "%VIEWER_EXE%" set "NEED_BUILD=1"
if "%NEED_BUILD%"=="0" (
  powershell -NoProfile -Command "$exe=Get-Item -LiteralPath '%VIEWER_EXE%'; $paths=@('%VIEWER_DIR%\lib','%VIEWER_DIR%\pubspec.yaml','%VIEWER_DIR%\pubspec.lock'); $latest=Get-ChildItem -LiteralPath $paths -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1; if($latest -and $latest.LastWriteTimeUtc -gt $exe.LastWriteTimeUtc){ exit 1 } exit 0"
  if errorlevel 1 set "NEED_BUILD=1"
)
if "%NEED_BUILD%"=="1" (
  echo Viewer executable is missing or stale. Building now...
  call "%ROOT_DIR%\build_viewer.bat" /nopause
  if errorlevel 1 exit /b 1
)
if not exist "%VIEWER_EXE%" exit /b 1
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
echo Viewer run failed.
pause
exit /b 1
