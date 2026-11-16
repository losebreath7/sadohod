@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\gate.ps1" %*
set "result=%errorlevel%"
echo.
echo Exit code: %result%  (0 = green, 1 = red, 2 = partial run)
pause
exit /b %result%
