#!/usr/bin/env bash
# Snapshot separate public PostgreSQL and both user-data volumes.
# Does NOT touch the local sadohod_mvp_v0_2 installation.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."

envfile="${SADOHOD_PRODUCTION_ENV:-.env.production}"
if [[ ! -f "$envfile" ]]; then echo "Missing production environment" >&2; exit 1; fi
python3 tools/check_production_env.py --env "$envfile"
compose=(docker compose --env-file "$envfile" -f docker-compose.production.yml -p sadohod_public)
destination="${1:-$PWD/backups/production}"
mkdir -p "$destination"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp -d "$destination/.pending-${stamp}-XXXXXX")"
cleanup() { [[ -d "$tmp" ]] && rm -rf -- "$tmp"; }
trap cleanup EXIT

"${compose[@]}" exec -T db pg_dump -U sadohod -d sadohod --format=custom --no-owner > "$tmp/database.dump"
test -s "$tmp/database.dump"
"${compose[@]}" cp api:/app/backend/media/products/uploads "$tmp/uploads"
"${compose[@]}" cp api:/app/state "$tmp/state"
tar -czf "$tmp/user-volumes.tar.gz" -C "$tmp" uploads state
tar -tzf "$tmp/user-volumes.tar.gz" >/dev/null
test -s "$tmp/user-volumes.tar.gz"
rm -rf -- "$tmp/uploads" "$tmp/state"
(cd "$tmp" && sha256sum database.dump user-volumes.tar.gz > SHA256SUMS)
folder="$destination/$stamp"
if [[ -e "$folder" ]]; then echo "Backup destination already exists" >&2; exit 1; fi
mv "$tmp" "$folder"
trap - EXIT
echo "Backup created at $folder"
echo "Copy it to a secure OFF-SERVER destination and run restore drill."
