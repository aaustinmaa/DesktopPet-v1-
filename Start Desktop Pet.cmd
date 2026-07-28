@echo off
set "PET_EXE=%~dp0dist\SuWuDu\SuWuDu.exe"
if not exist "%PET_EXE%" (
  echo SuWuDu.exe was not found. Building it now...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
  if errorlevel 1 (
    echo Build failed. See the message above.
    pause
    exit /b 1
  )
)
start "" "%PET_EXE%"
