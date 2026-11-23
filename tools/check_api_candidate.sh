#!/usr/bin/env bash
# Read-only readiness probe against a specific VPS without changing public DNS.
# Usage: bash tools/check_api_candidate.sh <NEW_IPV4>
# Optional: SADOHOD_API_HOST=api-stage.sadohod.ru for a staging certificate.
set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: bash tools/check_api_candidate.sh NEW_IPV4" >&2
  exit 2
fi
candidate_ip="$(python3 - "$1" <<'PY'
import ipaddress
import sys
try:
    candidate = ipaddress.ip_address(sys.argv[1])
    if candidate.version != 4:
        raise ValueError("IPv4 required")
except ValueError as exc:
    sys.exit(f"Invalid candidate IPv4 address: {exc}")
print(candidate)
PY
)"

host="${SADOHOD_API_HOST:-api.sadohod.ru}"
if [[ ! "$host" =~ ^api(-[a-z0-9-]+)?\.sadohod\.ru$ ]]; then
  echo "Only Sadohod API hostnames are allowed" >&2
  exit 2
fi

# --resolve sends TLS/SNI and HTTP Host for the real hostname to a chosen IP.
# Certificate MUST be valid for this hostname; no -k / insecure bypass.
# A new VPS may need a staging hostname/certificate before DNS cutover.
response="$(curl --noproxy '*' --fail --silent --show-error \
  --connect-timeout 5 --max-time 30 \
  --resolve "$host:443:$candidate_ip" "https://$host/health")"

printf '%s' "$response" | python3 -c '
import json
import sys
try:
    health = json.load(sys.stdin)
except (ValueError, TypeError) as exc:
    sys.exit(f"Health response is not JSON: {exc}")
if health.get("status") != "ok":
    sys.exit("Health response is not OK")
if health.get("demo") is not False:
    sys.exit("Demo mode must be disabled")
if health.get("search_backend") != "clip":
    sys.exit("Production search backend must be OpenCLIP")
print("Candidate API health OK; no DNS change was made.")
print("Version:", health.get("full_version", "unknown"))
'
