@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -Action Install %*
set "result=%errorlevel%"
echo.
pause
exit /b %result%
