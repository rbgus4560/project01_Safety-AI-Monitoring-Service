@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "CLIENT_DIR=%ROOT_DIR%\safety_monitor_client"
set "BACKEND_DIR=%CLIENT_DIR%\embedded_backend"
set "SETTINGS_PATH=%CLIENT_DIR%\client_settings.json"
set "CLIENT_BUILD_DIR=%CLIENT_DIR%\build\windows\x64\runner\Release"
set "CLIENT_EXE=%CLIENT_BUILD_DIR%\safety_monitor_client.exe"
set "PYTHON_CMD=%ROOT_DIR%\.venv\Scripts\python.exe"
set "MODEL_DIR=%BACKEND_DIR%\app\analysis\models\weights"
set "MODEL_PATH=%MODEL_DIR%\best.pt"
set "ENGINE_PATH=%MODEL_DIR%\best.engine"
set "CLIENT_LOG_DIR=%ROOT_DIR%\logs"
set "SAFETY_MONITOR_LOG_FILE=%CLIENT_LOG_DIR%\client.log"

call :check_workspace_path
if errorlevel 1 goto :fail
if not exist "%CLIENT_LOG_DIR%" mkdir "%CLIENT_LOG_DIR%"

call "%ROOT_DIR%\install_dependencies.bat" client
if errorlevel 1 goto :fail

if not exist "%CLIENT_DIR%\pubspec.yaml" (
  echo Client project not found:
  echo   %CLIENT_DIR%\pubspec.yaml
  goto :fail
)
if not exist "%BACKEND_DIR%\main.py" (
  echo Embedded backend entry not found:
  echo   %BACKEND_DIR%\main.py
  goto :fail
)
if not exist "%MODEL_PATH%" if not exist "%ENGINE_PATH%" (
  echo No runtime model was found. Put best.pt or best.engine here:
  echo   %MODEL_DIR%
  goto :fail
)

"%PYTHON_CMD%" -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)" > nul 2>&1
if errorlevel 1 (
  echo Warning: CUDA is not available from this Python environment. The client may run slowly or fail if CUDA/TensorRT is required.
)

if exist "%ENGINE_PATH%" (
  echo Found TensorRT engine: %ENGINE_PATH%
) else if /I "%SAFETY_MONITOR_PREPARE_TENSORRT%"=="1" (
  echo Preparing TensorRT engine before launch...
  "%PYTHON_CMD%" "%BACKEND_DIR%\ensure_runtime_engine.py"
  if errorlevel 1 goto :fail
) else (
  echo No best.engine found. Launching with available model. Set SAFETY_MONITOR_PREPARE_TENSORRT=1 to build the engine first.
)

call :ensure_client_build
if errorlevel 1 goto :fail

set "DEFAULT_SERVER_URL=http://127.0.0.1:8000"
set "REMOTE_SERVER_URL="
if exist "%SETTINGS_PATH%" (
  for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$p='%SETTINGS_PATH%'; try { $json=Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; if($json.remote_server_base_url){ $json.remote_server_base_url } } catch {}"`) do set "REMOTE_SERVER_URL=%%i"
)
if not defined REMOTE_SERVER_URL (
  if not "%SAFETY_MONITOR_SERVER_URL%"=="" (set "REMOTE_SERVER_URL=%SAFETY_MONITOR_SERVER_URL%") else (set "REMOTE_SERVER_URL=%DEFAULT_SERVER_URL%")
)

echo Current remote server: %REMOTE_SERVER_URL%
set /p "INPUT_REMOTE_SERVER_URL=Enter remote server URL (press Enter to keep current): "
if not "%INPUT_REMOTE_SERVER_URL%"=="" set "REMOTE_SERVER_URL=%INPUT_REMOTE_SERVER_URL%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\update_client_settings.ps1" -SettingsPath "%SETTINGS_PATH%" -RemoteServerUrl "%REMOTE_SERVER_URL%"
if errorlevel 1 goto :fail

echo Stopping old local client runtime if needed...
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\stop_client_runtime.ps1" -ClientDir "%CLIENT_DIR%" -Port 8100

echo Checking server health at %REMOTE_SERVER_URL% ...
powershell -NoProfile -Command "try { $u='%REMOTE_SERVER_URL%'.TrimEnd('/') + '/health'; $r=Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 5; if($r.StatusCode -eq 200){ Write-Host 'Server health check succeeded.'; exit 0 } exit 1 } catch { Write-Host ('Server health check error: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 echo Warning: server health check failed. The client will still start.

start "Safety Monitor Client" /D "%CLIENT_BUILD_DIR%" "%CLIENT_EXE%"
exit /b 0

:ensure_client_build
set "NEED_BUILD=0"
if not exist "%CLIENT_EXE%" set "NEED_BUILD=1"
if "%NEED_BUILD%"=="0" (
  powershell -NoProfile -Command "$exe=Get-Item -LiteralPath '%CLIENT_EXE%'; $paths=@('%CLIENT_DIR%\lib','%CLIENT_DIR%\pubspec.yaml','%CLIENT_DIR%\pubspec.lock'); $latest=Get-ChildItem -LiteralPath $paths -Recurse -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1; if($latest -and $latest.LastWriteTimeUtc -gt $exe.LastWriteTimeUtc){ exit 1 } exit 0"
  if errorlevel 1 set "NEED_BUILD=1"
)
if "%NEED_BUILD%"=="1" (
  echo Client executable is missing or stale. Building now...
  call "%ROOT_DIR%\build_client.bat" /nopause
  if errorlevel 1 exit /b 1
)
if not exist "%CLIENT_EXE%" exit /b 1
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
echo Client run failed.
pause
exit /b 1
