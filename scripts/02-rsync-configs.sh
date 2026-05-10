#!/usr/bin/env bash
# Rsync all service configs from .222 to .2 BEFORE the physical drive swap.
#
# What this does:
#   1. Stops the migration-target containers on .222 so files are quiescent.
#   2. Pulls each service's config dir into /srv/appdata/<service>/ on .2.
#      - Sven-readable paths: plain rsync over SSH as sven.
#      - Root-readable-only paths (NPM letsencrypt): docker-tar pipe trick
#        (run alpine container on .222, it can read root files since dockerd is root).
#   3. Fixes ownership to 1000:1000 so the containers can write on first boot.
#
# Re-runnable. rsync is incremental, so if you re-run it only transfers diffs.
#
# Usage (on .2):
#   bash ~/homelab/scripts/02-rsync-configs.sh

set -euo pipefail

# Self-elevate to root so we can write under /srv
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

SRC_USER=sven
SRC_HOST=192.168.0.222
SVEN_KEY=/home/sven/.ssh/homelab_ed25519

SSH_OPTS=(-i "$SVEN_KEY" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
RSYNC_FLAGS=(-aHAX --numeric-ids --info=stats2,progress2)

ssh_src()    { ssh "${SSH_OPTS[@]}" "$SRC_USER@$SRC_HOST" "$@"; }
rsync_pull() {
  local src=$1 dest=$2
  mkdir -p "$dest"
  rsync "${RSYNC_FLAGS[@]}" -e "ssh ${SSH_OPTS[*]}" "$SRC_USER@$SRC_HOST:$src" "$dest"
}

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "Verifying SSH connectivity to ${SRC_HOST}"
ssh_src 'hostname; id sven'

# Containers to stop on .222 (running names from `docker ps`)
CONTAINERS=(
  vaultwarden
  jellyfin
  plex
  radarr
  sonarr
  prowlarr
  overseerr
  nginxproxymanager
  brilliant_teddy-main_app-1
  uplifting_jake-main_app-1
)

say "Stopping containers on .222 so files are quiescent"
for c in "${CONTAINERS[@]}"; do
  echo "  stop $c"
  ssh_src "docker stop '$c' >/dev/null 2>&1 || echo '    (not running or not found)'"
done

say "Rsyncing service configs (sven-readable paths)"

rsync_pull /DATA/AppData/vaultwarden/data/        /srv/appdata/vaultwarden/
rsync_pull /DATA/AppData/nginxproxymanager/data/  /srv/appdata/nginx-proxy-manager/data/
rsync_pull /DATA/AppData/prowlarr/config/         /srv/appdata/prowlarr/
rsync_pull /DATA/AppData/jellyfin/config/         /srv/appdata/jellyfin/
rsync_pull /DATA/AppData/overseerr/config/        /srv/appdata/overseerr/
rsync_pull /home/sven/server_data/appdata/plex/   /srv/appdata/plex/
rsync_pull /home/sven/server_data/appdata/radarr/ /srv/appdata/radarr/
rsync_pull /home/sven/server_data/appdata/sonarr/ /srv/appdata/sonarr/
# qbittorrent: linuxserver image expects /config/qBittorrent/ — preserve that inner name
rsync_pull /home/sven/server_data/appdata/qBittorrent/ /srv/appdata/qbittorrent/qBittorrent/

say "Pulling NPM letsencrypt via docker-tar pipe (root-only credentials inside)"
mkdir -p /srv/appdata/nginx-proxy-manager/letsencrypt
ssh_src 'docker run --rm -v /DATA/AppData/nginxproxymanager/etc/letsencrypt:/src:ro alpine tar -cf - -C /src .' \
  | tar -xpf - -C /srv/appdata/nginx-proxy-manager/letsencrypt/

say "Fixing ownership: chown -R 1000:1000 /srv/appdata"
chown -R 1000:1000 /srv/appdata

say "Sanity checks"
echo
echo "Sizes per service:"
du -sh /srv/appdata/* | sort -k1 -h
echo
echo "NPM letsencrypt symlinks (should show '-> ../../archive/...' lines, not regular files):"
ls -la /srv/appdata/nginx-proxy-manager/letsencrypt/live/ 2>/dev/null | head -10 || echo "  (no live/ dir — letsencrypt may not have any certs)"

cat <<'NEXT'

================================================================================
Configs synced. Containers on .222 are STOPPED.

Next steps (manual):
  1. On .222: cleanly power down so the media drives unmount safely:
       ssh homeserver "sudo shutdown -h now"

  2. Power down .2:
       sudo shutdown -h now

  3. Physically move the two 1.8 TB drives from .222 to .2.
     - Label them: Movies (UUID 6711febc...) and TVShows (UUID fbe28914...).

  4. Power on .2. Drives auto-mount via fstab (nofail = boot even if a drive misses).

  5. Run the bring-up script (will be created next):
       bash ~/homelab/scripts/03-bring-up-services.sh
================================================================================
NEXT
