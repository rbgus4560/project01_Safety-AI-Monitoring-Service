@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "LOCAL_FLUTTER=%ROOT_DIR%\flutter\bin\flutter.bat"
set "VENV_PYTHON=%ROOT_DIR%\.venv\Scripts\python.exe"
set "HAS_ERROR=0"

echo Safety Monitor environment check
echo Root:
echo   %ROOT_DIR%
echo.

call :check_path_policy
call :check_git
call :check_python
call :check_flutter
call :check_windows_build_tools
call :check_project_files

echo.
if "%HAS_ERROR%"=="0" (
  echo Environment check finished. No blocking issue was detected.
  exit /b 0
)

echo Environment check found blocking issues. Fix the messages above and retry.
exit /b 1

:check_path_policy
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "'%ROOT_DIR%'.Length"`) do set "ROOT_LEN=%%i"
echo Workspace path length: %ROOT_LEN%
if %ROOT_LEN% GEQ 80 (
  echo ERROR: workspace path is too long for stable Flutter Windows builds.
  echo Move the repository near a drive root, for example:
  echo   C:\safety_monitor_workspace
  echo   D:\safety_monitor_workspace
  set "HAS_ERROR=1"
) else (
  echo Workspace path policy: OK. Keep this repository near C:\ or D:\ root.
)
exit /b 0

:check_git
where git > nul 2>&1
if errorlevel 1 (
  echo Warning: git was not found in PATH.
  exit /b 0
)
git -C "%ROOT_DIR%" config core.longpaths true > nul 2>&1
for /f "usebackq delims=" %%i in (`git -C "%ROOT_DIR%" config --get core.longpaths`) do set "GIT_LONGPATHS=%%i"
echo Git core.longpaths: %GIT_LONGPATHS%
exit /b 0

:check_python
if exist "%VENV_PYTHON%" (
  echo Python venv: found
  "%VENV_PYTHON%" --version
  exit /b 0
)
echo Python venv: missing. Run install_dependencies.bat all
set "HAS_ERROR=1"
exit /b 0

:check_flutter
if exist "%LOCAL_FLUTTER%" (
  echo Flutter SDK: local workspace SDK found
  call "%LOCAL_FLUTTER%" --version > nul 2>&1
  if errorlevel 1 (
    echo Flutter SDK: found but could not run flutter --version.
    set "HAS_ERROR=1"
  )
  exit /b 0
)
where flutter > nul 2>&1
if errorlevel 1 (
  echo Flutter SDK: missing
  echo Put Flutter at %ROOT_DIR%\flutter or add flutter to PATH.
  set "HAS_ERROR=1"
  exit /b 0
)
echo Flutter SDK: PATH flutter found
flutter --version > nul 2>&1
if errorlevel 1 (
  echo Flutter SDK: PATH flutter exists but could not run flutter --version.
  set "HAS_ERROR=1"
)
exit /b 0

:check_windows_build_tools
set "VSWHERE_EXE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VS_NATIVE_READY="
set "SDK_READY="
if exist "%VSWHERE_EXE%" (
  for /f "usebackq delims=" %%i in (`"%VSWHERE_EXE%" -products * -requires Microsoft.VisualStudio.Workload.NativeDesktop Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_NATIVE_READY=%%i"
)
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$roots=@('C:\Program Files (x86)\Windows Kits\10\Include','C:\Program Files\Windows Kits\10\Include'); foreach($root in $roots){ if(Test-Path $root){ $dirs=Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending; if($dirs){ $dirs[0].FullName; break } } }"`) do set "SDK_READY=%%i"
if defined VS_NATIVE_READY (echo Visual Studio C++ tools: found) else (
  echo Visual Studio C++ tools: missing. Install "Desktop development with C++".
  set "HAS_ERROR=1"
)
if defined SDK_READY (echo Windows SDK: found) else (
  echo Windows SDK: missing. Install Windows 10/11 SDK from Visual Studio Installer.
  set "HAS_ERROR=1"
)
exit /b 0

:check_project_files
if exist "%ROOT_DIR%\safety_monitor_client\pubspec.yaml" (echo Client project: found) else (
  echo Client project: missing
  set "HAS_ERROR=1"
)
if exist "%ROOT_DIR%\safety_monitor_viewer\pubspec.yaml" (echo Viewer project: found) else (
  echo Viewer project: missing
  set "HAS_ERROR=1"
)
if exist "%ROOT_DIR%\safety_monitor_server\main.py" (echo Server project: found) else (
  echo Server project: missing
  set "HAS_ERROR=1"
)
exit /b 0
