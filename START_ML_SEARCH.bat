@echo off
setlocal
cd /d "%~dp0"
echo [Sadohod] Starting existing PostgreSQL and OpenCLIP-enabled API...
echo [Sadohod] Existing databases and Docker volumes will be preserved.
echo [Sadohod] First start requires downloading public model weights.
docker compose -f docker-compose.yml -f docker-compose.ml.yml up -d --build api
if errorlevel 1 (
  echo [ERROR] Could not start ML API. Check Docker Desktop and Compose logs.
  pause
  exit /b 1
)
echo.
echo [Sadohod] Checking API status. Photo categories require search_backend=clip.
echo Open http://localhost:8000/health once the API is ready.
echo If the API is not ready, check: docker compose -f docker-compose.yml -f docker-compose.ml.yml logs api --tail=100
pause
