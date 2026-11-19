#!/usr/bin/env bash
# Production backup, with an explicitly isolated synthetic QA mode for CI.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."

if [[ "${SADOHOD_BACKUP_QA:-0}" == "1" ]]; then
  # This is deliberately a different compose file, project and source service.
  # Never resolve qa mode to any production container or existing local project.
  compose=(docker compose -f docker-compose.backup-qa.yml -p sadohod_backup_qa)
  files_service=files
  uploads_path=/uploads
  state_path=/state
else
  envfile="${SADOHOD_PRODUCTION_ENV:-.env.production}"
  [[ -f "$envfile" ]] || { echo "Missing production environment" >&2; exit 1; }
  python3 tools/check_production_env.py --env "$envfile"
  compose=(docker compose --env-file "$envfile" -f docker-compose.production.yml -p sadohod_public)
  files_service=api
  uploads_path=/app/backend/media/products/uploads
  state_path=/app/state
fi

destination="${1:-$PWD/backups/production}"
mkdir -p "$destination"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp -d "$destination/.pending-${stamp}-XXXXXX")"
cleanup() { [[ -d "$tmp" ]] && rm -rf -- "$tmp"; }
trap cleanup EXIT

"${compose[@]}" exec -T db pg_dump -U sadohod -d sadohod --format=custom --no-owner > "$tmp/database.dump"
test -s "$tmp/database.dump"
# Docker compose cp must not rename or nest either directory unexpectedly.
"${compose[@]}" cp "$files_service:$uploads_path/." "$tmp/uploads"
"${compose[@]}" cp "$files_service:$state_path/." "$tmp/state"
test -d "$tmp/uploads" && test -d "$tmp/state"
(cd "$tmp" && find uploads state -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum > FILE_SHA256SUMS)
tar -czf "$tmp/user-volumes.tar.gz" -C "$tmp" uploads state
test -s "$tmp/user-volumes.tar.gz"
python3 tools/verify_backup_archive.py "$tmp/user-volumes.tar.gz" --check-only
rm -rf -- "$tmp/uploads" "$tmp/state"
(cd "$tmp" && sha256sum database.dump user-volumes.tar.gz FILE_SHA256SUMS > SHA256SUMS)
folder="$destination/$stamp"
[[ ! -e "$folder" ]] || { echo "Backup folder exists" >&2; exit 1; }
mv "$tmp" "$folder"
trap - EXIT
echo "Backup created at $folder"
echo "Keep a separate encrypted off-server copy and verify restore."
