#!/usr/bin/env bash
# Bootstrap the new server (.2) before the drive migration.
#   - installs docker + compose plugin
#   - adds sven to the docker group
#   - creates /mnt/media/{movies,tv,music} and /srv/{appdata,games}
#   - appends UUID-based fstab entries for the two media drives (idempotent)
#   - runs `mount -a` to validate fstab syntax
#
# Safe to re-run. Designed to be run BEFORE the media drives are physically
# installed — the fstab entries use `nofail` so the system still boots without them.
#
# Usage (on the new server, .2):
#   bash ~/homelab/scripts/01-bootstrap-new-server.sh

set -euo pipefail

# Self-elevate to root
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

TARGET_USER=sven
MOVIES_UUID=6711febc-286e-46ad-a80b-1b421d5f7aaf
TV_UUID=fbe28914-df5b-43d1-9ad3-b45dcb79efc0
FSTAB_OPTS='ext4 defaults,nofail,x-systemd.device-timeout=10 0 2'

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

say "Installing docker via the official convenience script"
if command -v docker >/dev/null 2>&1; then
  echo "docker already installed: $(docker --version)"
else
  curl -fsSL https://get.docker.com | sh
fi

say "Adding ${TARGET_USER} to the docker group"
if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  echo "${TARGET_USER} already in docker group"
else
  usermod -aG docker "$TARGET_USER"
  echo "Added. ${TARGET_USER} must log out and back in for the group to take effect."
fi

say "Creating directory tree"
mkdir -p /mnt/media/{movies,tv,music}
mkdir -p /srv/appdata /srv/games
chown "$TARGET_USER:$TARGET_USER" /srv/games
ls -la /mnt/media /srv

say "Appending fstab entries (idempotent)"
add_fstab_line() {
  local uuid=$1 mountpoint=$2
  if grep -q "$uuid" /etc/fstab; then
    echo "fstab already has entry for $uuid -> $mountpoint"
  else
    printf 'UUID=%s %-20s %s\n' "$uuid" "$mountpoint" "$FSTAB_OPTS" >> /etc/fstab
    echo "added: $mountpoint"
  fi
}
add_fstab_line "$MOVIES_UUID" /mnt/media/movies
add_fstab_line "$TV_UUID"     /mnt/media/tv

say "Validating fstab (drives not present yet — should succeed with no-op)"
mount -a

say "Final state"
echo "docker: $(docker --version)"
echo
echo "fstab tail:"
tail -5 /etc/fstab
echo
echo "Directories:"
ls -la /mnt/media /srv
echo
echo '\033[1;32mBootstrap complete. Next: cutover (stop services on .222, rsync configs, power down, swap drives, boot .2).\033[0m'
