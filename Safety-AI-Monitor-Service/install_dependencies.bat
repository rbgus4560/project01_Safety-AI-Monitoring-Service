@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "VENV_DIR=%ROOT_DIR%\.venv"
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"
set "MODE=%~1"

if "%MODE%"=="" set "MODE=all"
if /I not "%MODE%"=="server" if /I not "%MODE%"=="client" if /I not "%MODE%"=="all" (
  echo Usage: install_dependencies.bat [server^|client^|all]
  exit /b 1
)

call :check_workspace_path
if errorlevel 1 exit /b 1

if not exist "%VENV_DIR%\Scripts\python.exe" (
  echo Creating Python virtual environment:
  echo   %VENV_DIR%
  call :find_bootstrap_python
  if errorlevel 1 (
    echo Python was not found. Install Python 3.12 or add python to PATH.
    exit /b 1
  )
  call %BOOTSTRAP_PYTHON% -m venv "%VENV_DIR%"
  if errorlevel 1 (
    echo Failed to create virtual environment.
    exit /b 1
  )
)

if not exist "%PYTHON_EXE%" (
  echo Virtual environment python not found:
  echo   %PYTHON_EXE%
  exit /b 1
)

echo Python interpreter:
"%PYTHON_EXE%" -c "import sys; print(sys.executable)"

"%PYTHON_EXE%" -m pip install --upgrade pip
if errorlevel 1 exit /b 1

if /I "%MODE%"=="server" (
  call :ensure_server
  exit /b %ERRORLEVEL%
)

if /I "%MODE%"=="client" (
  call :ensure_client
  exit /b %ERRORLEVEL%
)

call :ensure_server
if errorlevel 1 exit /b 1
call :ensure_client
exit /b %ERRORLEVEL%

:check_workspace_path
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "'%ROOT_DIR%'.Length"`) do set "ROOT_LEN=%%i"
echo Workspace root:
echo   %ROOT_DIR%
echo Path length: %ROOT_LEN%
if %ROOT_LEN% GEQ 80 (
  echo.
  echo This workspace path is too long for stable Flutter Windows builds.
  echo Move the repository near a drive root, for example:
  echo   C:\safety_monitor_workspace
  echo   D:\safety_monitor_workspace
  exit /b 1
)
exit /b 0

:find_bootstrap_python
py -3.12 -c "import sys" > nul 2>&1
if not errorlevel 1 (
  set "BOOTSTRAP_PYTHON=py -3.12"
  exit /b 0
)
python -c "import sys" > nul 2>&1
if not errorlevel 1 (
  set "BOOTSTRAP_PYTHON=python"
  exit /b 0
)
exit /b 1

:ensure_server
if not exist "%ROOT_DIR%\requirements-server.txt" (
  echo requirements-server.txt not found.
  exit /b 1
)
echo Installing server dependencies...
"%PYTHON_EXE%" -m pip install -r "%ROOT_DIR%\requirements-server.txt"
if errorlevel 1 exit /b 1
"%PYTHON_EXE%" -c "import fastapi, uvicorn, websockets, pydantic, multipart, cv2, numpy"
if errorlevel 1 (
  echo Server dependency check failed.
  exit /b 1
)
echo Server dependencies are ready.
exit /b 0

:ensure_client
if not exist "%ROOT_DIR%\requirements.txt" (
  echo requirements.txt not found.
  exit /b 1
)
echo Installing client embedded-backend dependencies...
"%PYTHON_EXE%" -m pip install -r "%ROOT_DIR%\requirements.txt"
if errorlevel 1 exit /b 1
"%PYTHON_EXE%" -c "import fastapi, uvicorn, cv2, numpy, requests, yt_dlp, websockets, torch, ultralytics, onnx, onnxruntime"
if errorlevel 1 (
  echo Client dependency check failed.
  exit /b 1
)
echo Client dependencies are ready.
exit /b 0
