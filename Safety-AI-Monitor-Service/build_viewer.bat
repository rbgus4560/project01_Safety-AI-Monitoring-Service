@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "PROJECT_DIR=%ROOT_DIR%\safety_monitor_viewer"
set "FLUTTER_CMD="
set "PAUSE_ON_EXIT=1"
if /I "%~1"=="/nopause" set "PAUSE_ON_EXIT=0"
if /I "%~1"=="--no-pause" set "PAUSE_ON_EXIT=0"

call :find_flutter
if errorlevel 1 goto :fail
if not exist "%PROJECT_DIR%\pubspec.yaml" (
  echo Viewer project not found: %PROJECT_DIR%
  goto :fail
)

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "'%ROOT_DIR%'.Length"`) do set "ROOT_LEN=%%i"
echo Workspace root: %ROOT_DIR%
echo Path length: %ROOT_LEN%
if %ROOT_LEN% GEQ 80 (
  echo This path is too long. Move the repository near C:\ or D:\ root.
  goto :fail
)

echo Building Viewer directly from:
echo   %PROJECT_DIR%
pushd "%PROJECT_DIR%"
call "%FLUTTER_CMD%" clean
if errorlevel 1 goto :build_fail
call "%FLUTTER_CMD%" pub get
if errorlevel 1 goto :build_fail
call "%FLUTTER_CMD%" config --enable-windows-desktop
if errorlevel 1 goto :build_fail
if not exist "windows\flutter\CMakeLists.txt" (
  call "%FLUTTER_CMD%" create --platforms=windows .
  if errorlevel 1 goto :build_fail
)
call "%FLUTTER_CMD%" build windows
if errorlevel 1 goto :build_fail
popd

echo Viewer build finished.
if "%PAUSE_ON_EXIT%"=="1" pause
exit /b 0

:build_fail
popd
:fail
echo Viewer build failed.
if "%PAUSE_ON_EXIT%"=="1" pause
exit /b 1

:find_flutter
if exist "%ROOT_DIR%\flutter\bin\flutter.bat" (
  set "FLUTTER_CMD=%ROOT_DIR%\flutter\bin\flutter.bat"
  exit /b 0
)
for /f "delims=" %%i in ('where flutter.bat 2^>nul') do if not defined FLUTTER_CMD set "FLUTTER_CMD=%%i"
if defined FLUTTER_CMD exit /b 0
echo Flutter SDK not found. Add flutter\bin to PATH.
exit /b 1
