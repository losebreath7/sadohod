@echo off
setlocal
cd /d "%~dp0"
echo [Sadohod] Enabling local OpenCLIP in the existing Docker Compose project.
echo [Sadohod] Existing PostgreSQL data, media and Docker volumes are preserved.
echo.
docker compose -f docker-compose.yml -f docker-compose.ml.yml up -d db
if errorlevel 1 (
  echo [ERROR] Could not start existing PostgreSQL.
  pause
  exit /b 1
)
if not exist backups mkdir backups
for /f %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%T"
if not defined STAMP set STAMP=manual
echo [Sadohod] Backing up PostgreSQL before rebuilding the API...
docker compose -f docker-compose.yml -f docker-compose.ml.yml exec -T db pg_dump -U sadohod -d sadohod > "backups\ml_before_%STAMP%.sql"
if errorlevel 1 (
  del "backups\ml_before_%STAMP%.sql" >nul 2>nul
  echo [ERROR] Database backup failed. API was not changed.
  pause
  exit /b 1
)
echo [Sadohod] SQL backup saved in backups\ml_before_%STAMP%.sql
echo [Sadohod] Building CPU OpenCLIP API; weights download is required on first launch.
docker compose -f docker-compose.yml -f docker-compose.ml.yml up -d --build api
if errorlevel 1 (
  echo [ERROR] Could not start ML API. Check Docker Desktop and Compose logs.
  pause
  exit /b 1
)
echo.
echo [Sadohod] Once ready, check http://localhost:8000/health
echo photo_categories must be true and search_backend must be clip.
echo Logs: docker compose -f docker-compose.yml -f docker-compose.ml.yml logs api --tail=100
pause
