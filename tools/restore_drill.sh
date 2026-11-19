#!/usr/bin/env bash
# Restores a BACKUP to a dedicated disposable PostgreSQL volume, never production.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."
if [[ "$#" -ne 1 ]]; then echo "Usage: bash tools/restore_drill.sh BACKUP_DIRECTORY" >&2; exit 2; fi
folder="$(realpath "$1")"
for file in database.dump user-volumes.tar.gz SHA256SUMS; do
  [[ -s "$folder/$file" ]] || { echo "Missing backup part: $file" >&2; exit 1; }
done
(cd "$folder" && sha256sum -c SHA256SUMS)
tar -tzf "$folder/user-volumes.tar.gz" >/dev/null
if docker volume inspect sadohod_restore_drill_restore_pg >/dev/null 2>&1; then
  echo "Drill volume already exists. Refusing to overwrite; use a fresh test environment." >&2
  exit 1
fi
envfile="${SADOHOD_PRODUCTION_ENV:-.env.production}"
python3 tools/check_production_env.py --env "$envfile"
compose=(docker compose --env-file "$envfile" -f docker-compose.restore-drill.yml -p sadohod_restore_drill)
"${compose[@]}" up -d --wait db
"${compose[@]}" exec -T db pg_restore --list < "$folder/database.dump" >/dev/null
"${compose[@]}" exec -T db pg_restore -U sadohod -d sadohod \
    --no-owner --no-privileges --exit-on-error < "$folder/database.dump"
temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
tar -xzf "$folder/user-volumes.tar.gz" -C "$temp"
test -d "$temp/uploads" && test -d "$temp/state"
"${compose[@]}" exec -T db psql -U sadohod -d sadohod -Atc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'"
echo "Recovery drill restored database, uploads and admin-state archive to an isolated test location."
echo "Drill volume remains isolated: sadohod_restore_drill_restore_pg; delete it only intentionally after review."
