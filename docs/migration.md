# Migration plan: .222 → .2

Source: `sven@192.168.0.222` (CasaOS, Ubuntu 5.15)
Target: `sven@192.168.0.2`

## New filesystem layout on .2

All CasaOS-isms are gone. Clean tree:

```
/mnt/media/movies/                <- drive 1 mountpoint (was /DATA/Media/Movies)
/mnt/media/tv/                    <- drive 2 mountpoint (was /DATA/Media/TVShows)
/mnt/media/music/                 <- empty dir on root fs

/srv/appdata/jellyfin/            (was /DATA/AppData/jellyfin/config)
/srv/appdata/plex/                (was /home/sven/server_data/appdata/plex)
/srv/appdata/radarr/              (was /home/sven/server_data/appdata/radarr)
/srv/appdata/sonarr/              (was /home/sven/server_data/appdata/sonarr)
/srv/appdata/qbittorrent/         (was /home/sven/server_data/appdata, partial)
/srv/appdata/prowlarr/            (was /DATA/AppData/prowlarr/config)
/srv/appdata/overseerr/           (was /DATA/AppData/overseerr/config)
/srv/appdata/nginx-proxy-manager/ (was /DATA/AppData/nginxproxymanager)
/srv/appdata/vaultwarden/         (was /DATA/AppData/vaultwarden/data)
```

## Drive identities

| Source drive on .222 | Filesystem UUID                        | New mountpoint on .2 |
| -------------------- | -------------------------------------- | -------------------- |
| `/dev/sda1`          | `6711febc-286e-46ad-a80b-1b421d5f7aaf` | `/mnt/media/movies`  |
| `/dev/sdc1`          | `fbe28914-df5b-43d1-9ad3-b45dcb79efc0` | `/mnt/media/tv`      |

Both drives are 1.8 TB ext4, no RAID, no LVM. UUIDs survive the physical move.

## Pre-flight on .2

```sh
ssh homeserver-new

# 1. Docker + compose plugin
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker sven
# log out, back in

# 2. Make sure sven is uid=1000 / gid=1000 (the files on the moved drives are owned by 1000:1000)
id sven
# if wrong: sudo usermod -u 1000 sven && sudo groupmod -g 1000 sven

# 3. Make mountpoints
sudo mkdir -p /mnt/media/{movies,tv,music}
sudo mkdir -p /srv/appdata /srv

# 4. Add the two drives to /etc/fstab (UUID-based, immune to /dev/sd? reordering)
sudo tee -a /etc/fstab <<'EOF'
UUID=6711febc-286e-46ad-a80b-1b421d5f7aaf /mnt/media/movies ext4 defaults,nofail,x-systemd.device-timeout=10 0 2
UUID=fbe28914-df5b-43d1-9ad3-b45dcb79efc0 /mnt/media/tv     ext4 defaults,nofail,x-systemd.device-timeout=10 0 2
EOF

# 5. Mount and verify (after physically installing the two drives)
sudo mount -a
findmnt /mnt/media/movies
findmnt /mnt/media/tv
ls /mnt/media/movies | head     # should show your movie folders, owned by 1000:1000

# 6. Clone this repo
git clone <repo-url> ~/homelab
```

## Migration order

Stateless / smallest first, then heavy:

1. **vaultwarden** (small, easy to verify, critical so prove it works first)
2. **nginx-proxy-manager** (so you can repoint hostnames as services move)
3. **cloudflare-ddns** (point the dynamic DNS at the new public IP)
4. ***arr stack**: prowlarr → sonarr → radarr → overseerr (config only — small)
5. **qbittorrent** (config only)
6. **plex, jellyfin** (config only — media library comes via the physical drive move)

The media library — `/DATA/Media/Movies` and `/DATA/Media/TVShows` on the
source — does **not** need rsync. The two drives are being physically moved
and re-mounted at `/mnt/media/movies` and `/mnt/media/tv`. That saves ~3.1 TB
of network transfer.

## Per-service rsync (config data only)

Each command rsyncs the small config payload from .222 (still running CasaOS
paths) into the new clean structure on .2. Run these from `.2`.

```sh
RSYNC="sudo rsync -aHAX --numeric-ids --info=progress2 -e 'ssh -i /home/sven/.ssh/homelab_ed25519'"

# Stop the corresponding container on .222 first so its files are quiescent:
ssh sven@192.168.0.222 "docker stop vaultwarden"

# Then for each service:
sudo mkdir -p /srv/appdata/vaultwarden
$RSYNC sven@192.168.0.222:/DATA/AppData/vaultwarden/data/ /srv/appdata/vaultwarden/

sudo mkdir -p /srv/appdata/nginx-proxy-manager/{data,letsencrypt}
$RSYNC sven@192.168.0.222:/DATA/AppData/nginxproxymanager/data/        /srv/appdata/nginx-proxy-manager/data/
$RSYNC sven@192.168.0.222:/DATA/AppData/nginxproxymanager/etc/letsencrypt/ /srv/appdata/nginx-proxy-manager/letsencrypt/

sudo mkdir -p /srv/appdata/prowlarr
$RSYNC sven@192.168.0.222:/DATA/AppData/prowlarr/config/ /srv/appdata/prowlarr/

sudo mkdir -p /srv/appdata/sonarr
$RSYNC sven@192.168.0.222:/home/sven/server_data/appdata/sonarr/ /srv/appdata/sonarr/

sudo mkdir -p /srv/appdata/radarr
$RSYNC sven@192.168.0.222:/home/sven/server_data/appdata/radarr/ /srv/appdata/radarr/

sudo mkdir -p /srv/appdata/overseerr
$RSYNC sven@192.168.0.222:/DATA/AppData/overseerr/config/ /srv/appdata/overseerr/

# qbittorrent needs the qBittorrent (cap B) subfolder preserved — that's where the linuxserver image stores config:
sudo mkdir -p /srv/appdata/qbittorrent
$RSYNC sven@192.168.0.222:/home/sven/server_data/appdata/qBittorrent/ /srv/appdata/qbittorrent/qBittorrent/

sudo mkdir -p /srv/appdata/plex
$RSYNC sven@192.168.0.222:/home/sven/server_data/appdata/plex/ /srv/appdata/plex/

sudo mkdir -p /srv/appdata/jellyfin
$RSYNC sven@192.168.0.222:/DATA/AppData/jellyfin/config/ /srv/appdata/jellyfin/

# Fix ownership in one shot (rsync preserves uid 1000, but the parent dirs we mkdir'd are root-owned):
sudo chown -R 1000:1000 /srv/appdata
```

Then for each service, bring it up:

```sh
cd ~/homelab/services/<name>
[ -f .env.example ] && cp .env.example .env && $EDITOR .env
docker compose up -d
docker compose logs -f
```

## Network / DNS cutover

Once services are healthy on .2:

1. Update `nginx-proxy-manager` upstreams on .2 (or skip — they migrate over with the rsync; just sanity-check after first boot).
2. Update router port forwards (80 → 192.168.0.2:180, 443 → 192.168.0.2:1443) instead of .222.
3. Update LAN DNS / Pi-hole if you have one pointing `*.neka.hr` at .222.
4. `cloudflare-ddns` on .2 will update DNS automatically — but since the public IP probably hasn't changed (same router), this is mostly a no-op.
5. **Rotate the Cloudflare API token** (it was exposed in conversation logs during this migration). Generate a new one in Cloudflare dashboard, update `services/cloudflare-ddns/.env`, restart the container.

## Things to clean up after migration

- Delete the empty `/DATA/Media/TV Shows` (with space) directory on the source — pure noise.
- Pin image tags for stability-critical services (consider pinning vaultwarden, nginx-proxy-manager).
