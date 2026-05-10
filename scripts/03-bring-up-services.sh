#!/usr/bin/env bash
# Bring up all homelab services in a sensible order.
# Run on .2 as sven (no sudo needed — sven is in the docker group).
#
# Pre-conditions (verified before any service starts):
#   - /mnt/media/movies and /mnt/media/tv are actually mounted
#   - /srv/appdata/<service>/ exists and is owned by 1000:1000
#   - .env files exist for services that require them

set -uo pipefail   # NOT -e: we want every service to try, not bail on first error

REPO="$HOME/homelab"
ORDER=(
  nginx-proxy-manager
  vaultwarden
  cloudflare-ddns
  prowlarr
  sonarr
  radarr
  overseerr
  qbittorrent
  plex
  jellyfin
)
REQUIRES_ENV=(vaultwarden cloudflare-ddns)

say()   { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()    { printf '\033[1;32m  ✓ %s\033[0m\n' "$*"; }
fail()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*"; }

# --- Pre-flight ---
say "Pre-flight checks"
preflight_failed=0

for mp in /mnt/media/movies /mnt/media/tv; do
  if findmnt "$mp" >/dev/null 2>&1; then
    ok "$mp mounted"
  else
    fail "$mp NOT mounted"
    preflight_failed=1
  fi
done

for svc in "${REQUIRES_ENV[@]}"; do
  if [ -f "$REPO/services/$svc/.env" ]; then
    ok "$svc/.env present"
  else
    fail "$svc/.env missing — service will not start cleanly"
    preflight_failed=1
  fi
done

if [ $preflight_failed -ne 0 ]; then
  echo
  echo "Aborting — fix pre-flight failures above and rerun."
  exit 1
fi

# --- Bring up each service ---
failed=()
for svc in "${ORDER[@]}"; do
  say "$svc"
  if cd "$REPO/services/$svc" 2>/dev/null && docker compose up -d; then
    ok "$svc started"
  else
    fail "$svc FAILED"
    failed+=("$svc")
  fi
done

# --- Status summary ---
say "Status (give it 10s then re-run 'docker ps' if anything's still 'starting')"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

if [ ${#failed[@]} -ne 0 ]; then
  echo
  fail "Services that failed: ${failed[*]}"
  echo "  Inspect with: cd ~/homelab/services/<svc> && docker compose logs --tail=50"
  exit 1
fi

echo
ok "All services brought up. Next: verify each in browser, then update router port forwards from .222 → .2."
