# Penpot 24/7 High-Availability Production Stack

This directory contains the production stack and scripts to run Penpot 2.19
24/7.

## Architecture Overview

```
                          Internet / Clients
                                 |
                                 v (Port 80/443)
                    +-------------------------+
                    |      Caddy (TLS/WSS)    |  <-- Automatic Let's Encrypt TLS
                    +------------+------------+
                                 | (Internal Docker Network)
                                 v
                    +-------------------------+
                    |     penpot-frontend     |  <-- Local debug: 127.0.0.1:9001
                    +------------+------------+
         +-----------------------+-----------------------+
         |                       |                       |
         v                       v                       v
+------------------+   +------------------+   +------------------+
|  penpot-backend  |   |  penpot-exporter |   | penpot-admin     |
|  (Worker + API)  |   |  (PDF/SVG render)|   | console          |
+--------+---------+   +--------+---------+   +------------------+
         |                      |
         +----------------------+--------+
         v                               v
+------------------+            +------------------+
| penpot-postgres  |            |  penpot-valkey   |
| (Data checksums) |            | (Redis bus/cache)|
+------------------+            +------------------+
```

## Key Features for 24/7 Operation

1. **Automatic TLS & WebSocket Routing ([`Caddyfile`](Caddyfile)):**
   - Provisions and renews Let's Encrypt certificates.
   - Proxies persistent WebSocket connections (`/ws/notifications`) with 300s
     timeouts.
   - Matches Penpot's 350 MB upload limit and adds `Strict-Transport-Security`.

2. **Strict Loopback Binding:**
   - Backend, Valkey, and Postgres expose no host ports.
   - `penpot-frontend` binds only to `127.0.0.1:9001`.
   - Caddy binds to `127.0.0.1` by default (`PENPOT_HTTP_BIND` /
     `PENPOT_HTTPS_BIND`). Set those to `0.0.0.0` only on a public edge host.

3. **Log Rotation (`json-file`):**
   - Every container caps logs at `max-size: 20m` and `max-file: 5`.

4. **Health Checks & Auto-Restart:**
   - Readiness probes (`/readyz`) run on frontend, backend, and exporter, plus
     `pg_isready` on Postgres and `valkey-cli ping` on Valkey.
   - [`scripts/watchdog.sh`](scripts/watchdog.sh) restarts unhealthy or stalled
     containers.

5. **Backups & Recovery:**
   - [`scripts/backup.sh`](scripts/backup.sh) dumps PostgreSQL (`--clean
     --if-exists`), archives the assets volume, writes `SHA256SUMS`, and prunes
     backups older than 7 days.
   - [`scripts/restore.sh`](scripts/restore.sh) verifies `SHA256SUMS` before
     restoring PostgreSQL and assets.

6. **Systemd Supervision:**
   - [`systemd/penpot.service`](systemd/penpot.service) starts the stack at boot.
   - `penpot-backup.timer` runs daily backups at 03:00.
   - `penpot-watchdog.timer` runs the health watchdog every 2 minutes.

## Quick Start

### 1. Initialize `.env`

```bash
cd deploy/production
./penpot-ctl.sh init
```

`init` copies `.env.production.example` to `.env`, generates strong random
values for `PENPOT_SECRET_KEY` and `POSTGRES_PASSWORD`, and sets permissions to
`600`. Edit `.env` to set `PENPOT_DOMAIN`, `PENPOT_PUBLIC_URI`, `ACME_EMAIL`,
and your SMTP credentials.

### 2. Start the Stack

```bash
./penpot-ctl.sh start
```

### 3. Check Status

```bash
./penpot-ctl.sh status
```

## Operations CLI (`penpot-ctl.sh`)

| Command | Action |
|---|---|
| `./penpot-ctl.sh init [--force]` | Create `.env` with generated secrets |
| `./penpot-ctl.sh start` | Boot all services and wait on health checks |
| `./penpot-ctl.sh stop` | Stop all services |
| `./penpot-ctl.sh restart` | Restart all services |
| `./penpot-ctl.sh status` | Show container state and health |
| `./penpot-ctl.sh logs [service]` | Follow container logs |
| `./penpot-ctl.sh backup` | Run a full database and assets backup |
| `./penpot-ctl.sh restore <dir>` | Restore database and assets from a backup |
| `./penpot-ctl.sh update` | Pull Penpot 2.19 images and recreate containers |
| `./penpot-ctl.sh check-ports` | Inspect published container ports |

## Systemd Setup (Linux Host)

Copy the repo to `/opt/penpot` (or adjust `WorkingDirectory` and `ExecStart`
paths in the unit files), then install and enable the units:

```bash
sudo cp systemd/penpot.service /etc/systemd/system/
sudo cp systemd/penpot-backup.* /etc/systemd/system/
sudo cp systemd/penpot-watchdog.* /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now penpot.service
sudo systemctl enable --now penpot-backup.timer
sudo systemctl enable --now penpot-watchdog.timer
```
