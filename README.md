# homelab

Docker compose stacks for the home server. Pulled from a CasaOS install on
`192.168.0.222`; intended to run on `192.168.0.2` after migration.

## Layout

```
services/                      # one folder per service, each independently `docker compose up -d`-able
  cloudflare-ddns/
  jellyfin/
  nginx-proxy-manager/
  overseerr/
  plex/
  prowlarr/
  qbittorrent/
  radarr/
  sonarr/
  vaultwarden/
docs/
  migration.md                 # step-by-step plan to move from .222 to .2
```

## Filesystem layout on the host

```
/mnt/media/movies/             # mountpoint for drive 1 (1.8 TB ext4, ex-/dev/sda1)
/mnt/media/tv/                 # mountpoint for drive 2 (1.8 TB ext4, ex-/dev/sdc1)
/mnt/media/music/              # empty dir on root fs

/srv/appdata/<service>/        # per-service config (was scattered across /DATA/AppData and /home/sven/server_data/appdata)
```

## Running a service

```sh
cd services/<name>
cp .env.example .env    # only if a .env.example exists
$EDITOR .env            # fill in any blanks
docker compose up -d
```

Services that need a `.env`:
- `vaultwarden/` — `ADMIN_TOKEN` (argon2id hash)
- `cloudflare-ddns/` — `CLOUDFLARE_API_TOKEN`, `DOMAINS`

Most other services honour optional `PUID`, `PGID`, and `TZ` overrides via
shell environment; defaults are `1000 / 1000 / Europe/Zagreb`.
