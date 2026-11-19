#!/usr/bin/env bash
# Restore into dedicated, NEW drill volumes. No interaction with production.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."
if [[ "$#" -ne 1 ]]; then
  echo "Usage: bash tools/restore_drill.sh BACKUP_DIRECTORY" >&2; exit 2
fi
folder="$(realpath "$1")"
for file in database.dump user-volumes.tar.gz SHA256SUMS FILE_SHA256SUMS; do
  [[ -s "$folder/$file" ]] || { echo "Missing or empty backup part: $file" >&2; exit 1; }
done
# Validate all hashes and archive safety BEFORE creating any Docker volumes.
(cd "$folder" && sha256sum -c SHA256SUMS)
python3 tools/verify_backup_archive.py "$folder/user-volumes.tar.gz" --check-only
envfile="${SADOHOD_PRODUCTION_ENV:-.env.production}"
python3 tools/check_production_env.py --env "$envfile"
compose=(docker compose --env-file "$envfile" -f docker-compose.restore-drill.yml -p sadohod_restore_drill)

for name in restore_pg restore_uploads restore_admin_state; do
  if docker volume inspect "sadohod_restore_drill_$name" >/dev/null 2>&1; then
    echo "Refusing to overwrite existing drill volume: $name" >&2
    exit 1
  fi
done

temp="$(mktemp -d)"
trap 'rm -rf -- "$temp"' EXIT
python3 tools/verify_backup_archive.py "$folder/user-volumes.tar.gz" --destination "$temp"
cp "$folder/FILE_SHA256SUMS" "$temp/FILE_SHA256SUMS"
(cd "$temp" && sha256sum -c FILE_SHA256SUMS)

# Separate database and filesystem volumes; only the named drill Compose file.
"${compose[@]}" up -d --wait db
"${compose[@]}" exec -T db pg_restore --list < "$folder/database.dump" >/dev/null
"${compose[@]}" exec -T db pg_restore -U sadohod -d sadohod \
    --no-owner --no-privileges --exit-on-error < "$folder/database.dump"
"${compose[@]}" run --rm --no-deps -v "$temp:/restore:ro" files \
    'set -eu; cp -a /restore/uploads/. /uploads/; cp -a /restore/state/. /state/; cd /; sha256sum -c /restore/FILE_SHA256SUMS'
table_count="$("${compose[@]}" exec -T db psql -U sadohod -d sadohod -Atc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'")"
[[ "$table_count" =~ ^[0-9]+$ ]] && (( table_count > 0 )) || {
  echo "Recovery database has no user tables" >&2
  exit 1
}
echo "Recovery drill OK: PostgreSQL restored; uploads and state restored to NEW Docker volumes with SHA256 verification."
echo "Drill volumes remain isolated. Do not run docker compose down -v or remove working volumes."
