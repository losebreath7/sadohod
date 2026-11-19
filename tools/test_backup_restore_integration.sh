#!/usr/bin/env bash
# CI integration: synthetic DB -> real backup -> NEW drill volumes -> checks.
# No local/production project, credentials or volumes are used.
set -Eeuo pipefail
umask 077
cd "$(dirname "$0")/.."
qa=(docker compose -f docker-compose.backup-qa.yml -p sadohod_backup_qa)
drill=(docker compose --env-file "$PWD/.env.production.example" -f docker-compose.restore-drill.yml -p sadohod_restore_drill)
for name in sadohod_backup_qa_qa_pg sadohod_backup_qa_qa_uploads \
            sadohod_backup_qa_qa_admin_state sadohod_restore_drill_restore_pg \
            sadohod_restore_drill_restore_uploads sadohod_restore_drill_restore_admin_state; do
  if docker volume inspect "$name" >/dev/null 2>&1; then
    echo "Pre-existing test volume $name: refusing to touch any data" >&2
    exit 1
  fi
done
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"; "${qa[@]}" down || true; "${drill[@]}" down || true' EXIT
# All values below are synthetic. Environment is valid but is never sent to a network endpoint.
cat > "$tmp/qa.env" <<'ENV'
SADOHOD_ENV=production
DEMO_SEED=0
API_DOMAIN=api.sadohod.qa-example.org
POSTGRES_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
ADMIN_TOKEN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SMTP_HOST=smtp.sadohod.qa-example.org
SMTP_PORT=465
SMTP_FROM=qa@sadohod.qa-example.org
SMTP_USER=qa@sadohod.qa-example.org
SMTP_PASSWORD=cccccccccccccccccccc
ALLOWED_ORIGINS=
PHOTO_SEARCH_MIN_SCORE=0.20
ENV
"${qa[@]}" up -d --wait db files
"${qa[@]}" exec -T db psql -v ON_ERROR_STOP=1 -U sadohod -d sadohod <<'SQL'
CREATE TABLE qa_sellers (id INTEGER PRIMARY KEY, title TEXT NOT NULL);
CREATE TABLE qa_products (id INTEGER PRIMARY KEY, seller_id INTEGER NOT NULL REFERENCES qa_sellers(id), title TEXT NOT NULL);
CREATE TABLE qa_images (id INTEGER PRIMARY KEY, product_id INTEGER NOT NULL REFERENCES qa_products(id), filename TEXT NOT NULL);
INSERT INTO qa_sellers VALUES (7, 'Synthetic seller');
INSERT INTO qa_products VALUES (42, 7, 'Synthetic jacket');
INSERT INTO qa_images VALUES (501, 42, 'synthetic.jpg'), (502, 42, 'second.jpg');
SQL
"${qa[@]}" exec -T files sh -ec '
  mkdir -p /uploads /state
  printf "synthetic photo pixels 501\n" > /uploads/synthetic.jpg
  printf "synthetic photo pixels 502\n" > /uploads/second.jpg
  printf "synthetic admin token state not valid\n" > /state/admin-token.txt
  printf "{\"reviewed\": 2}\n" > /state/moderation.json
'
"${qa[@]}" exec -T db psql -U sadohod -d sadohod -Atc \
  "SELECT p.id || ':' || s.title || ':' || string_agg(i.filename, ',' ORDER BY i.id) FROM qa_products p JOIN qa_sellers s ON p.seller_id=s.id JOIN qa_images i ON i.product_id=p.id GROUP BY p.id,s.title" \
  > "$tmp/source-relations.txt"
[[ "$(cat "$tmp/source-relations.txt")" == "42:Synthetic seller:synthetic.jpg,second.jpg" ]]

SADOHOD_BACKUP_QA=1 bash tools/backup_production.sh "$tmp/backups"
folder="$(find "$tmp/backups" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -n "$folder" ]] && test -s "$folder/database.dump"

# Corruption and missing-file failures MUST happen before any recovery volume is created.
mkdir -p "$tmp/tampered"
cp "$folder/"* "$tmp/tampered/"
printf "tampering" >> "$tmp/tampered/user-volumes.tar.gz"
if SADOHOD_PRODUCTION_ENV="$tmp/qa.env" bash tools/restore_drill.sh "$tmp/tampered"; then
  echo "Corrupted archive was accepted" >&2; exit 1
fi
mkdir -p "$tmp/missing"
cp "$folder/database.dump" "$folder/SHA256SUMS" "$folder/FILE_SHA256SUMS" "$tmp/missing/"
if SADOHOD_PRODUCTION_ENV="$tmp/qa.env" bash tools/restore_drill.sh "$tmp/missing"; then
  echo "Incomplete backup was accepted" >&2; exit 1
fi
if docker volume inspect sadohod_restore_drill_restore_pg >/dev/null 2>&1; then
  echo "Restore created volumes from invalid archive" >&2; exit 1
fi

SADOHOD_PRODUCTION_ENV="$tmp/qa.env" bash tools/restore_drill.sh "$folder"
"${drill[@]}" exec -T db psql -U sadohod -d sadohod -Atc \
  "SELECT p.id || ':' || s.title || ':' || string_agg(i.filename, ',' ORDER BY i.id) FROM qa_products p JOIN qa_sellers s ON p.seller_id=s.id JOIN qa_images i ON i.product_id=p.id GROUP BY p.id,s.title" \
  > "$tmp/recovered-relations.txt"
cmp "$tmp/source-relations.txt" "$tmp/recovered-relations.txt"
# Both original QA and restored files are independently checked against the same checksums.
"${qa[@]}" exec -T files sh -ec '
  test "$(cat /uploads/synthetic.jpg)" = "synthetic photo pixels 501"
  test "$(cat /state/moderation.json)" = "{\"reviewed\": 2}"
'
"${drill[@]}" run --rm --no-deps -v "$folder:/backup:ro" files \
  'cd /; sha256sum -c /backup/FILE_SHA256SUMS'
# An existing drill MUST never be silently overwritten or modified.
if SADOHOD_PRODUCTION_ENV="$tmp/qa.env" bash tools/restore_drill.sh "$folder"; then
  echo "Repeated restoration overwrote a populated drill" >&2; exit 1
fi
echo "ISOLATED BACKUP/RESTORE E2E: PostgreSQL rows, photo bytes and admin files MATCH"
