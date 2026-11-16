@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0tools\check.ps1"
