@echo off
setlocal
cd /d "%~dp0"
docker compose -p sadohod_isolated_qa -f tools\compose.qa.yml up --build --abort-on-container-exit --exit-code-from tests
set "result=%errorlevel%"
docker compose -p sadohod_isolated_qa -f tools\compose.qa.yml down
echo Test exit code: %result%
pause
exit /b %result%
