@echo off
setlocal
title Radio Meta ICY and ffprobe Diagnostic

echo Radio Meta ICY and ffprobe diagnostic
echo.
if not exist "%~dp0Inspect-RadioStream.ps1" (
  echo Inspect-RadioStream.ps1 was not found beside this CMD file.
  pause
  exit /b 2
)
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo Windows PowerShell was not found.
  pause
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Inspect-RadioStream.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Diagnostic exited with code %RC%. See the console error and any partial report files.
pause
exit /b %RC%
