#!/usr/bin/env bash
# Snapshot public PostgreSQL, seller uploads and private admin state.
# Run on VPS with bash, Docker Compose, gzip and tar. Never commit backups.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."
if [[ ! -f .env.public ]]; then
  echo "Missing .env.public" >&2; exit 1
fi
compose=(docker compose --env-file .env.public
  -f docker-compose.yml -f docker-compose.ml.yml -f docker-compose.public.yml
  -p sadohod_public)
destination="${1:-$PWD/backups/public}"
mkdir -p "$destination"
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp -d "$destination/.pending-${stamp}-XXXXXX")"
cleanup() { [[ -d "$tmp" ]] && rm -rf "$tmp"; }
trap cleanup EXIT
"${compose[@]}" exec -T db pg_dump --format=custom -U sadohod -d sadohod > "$tmp/database.dump"
test -s "$tmp/database.dump"
"${compose[@]}" cp api:/app/backend/media/products/uploads "$tmp/"
"${compose[@]}" cp api:/app/state "$tmp/"
tar -czf "$tmp/volumes.tar.gz" -C "$tmp" uploads state
rm -rf "$tmp/uploads" "$tmp/state"
sha256sum "$tmp/database.dump" "$tmp/volumes.tar.gz" > "$tmp/SHA256SUMS"
folder="$destination/$stamp"
mv "$tmp" "$folder"
trap - EXIT
echo "Backup created at $folder"
echo "Copy off-server and verify restore before production."
