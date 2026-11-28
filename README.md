# FreePBX 17 + Asterisk 22 LTS + MariaDB (All-in-One Docker)

[![Build, Test, and Publish](https://github.com/ltfnproject/freepbx-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/ltfnproject/freepbx-docker/actions/workflows/docker-publish.yml)
[![Docker Hub](https://img.shields.io/docker/v/ltfnproject/freepbx?sort=semver&label=Docker%20Hub)](https://hub.docker.com/r/ltfnproject/freepbx)
[![Docker Image Size](https://img.shields.io/docker/image-size/ltfnproject/freepbx/latest)](https://hub.docker.com/r/ltfnproject/freepbx)

[![Language: English](https://img.shields.io/badge/Language-English-2563eb?style=for-the-badge)](https://github.com/ltfnproject/freepbx-docker/blob/main/README.md)
[![Bahasa Indonesia](https://img.shields.io/badge/Language-Bahasa%20Indonesia-64748b?style=for-the-badge)](https://github.com/ltfnproject/freepbx-docker/blob/main/README.id.md)

A self-contained, pre-initialized **FreePBX 17 Stable + Asterisk 22 LTS + MariaDB (embedded)** Docker image built on **Debian 12 (Bookworm)** (~486 MB compressed). Designed for fast startup (**~10–20 seconds**) and effortless deployment using a single `docker-compose.yml` without waiting for first-boot module or database initialization—ideal for **VoIP/networking labs, education, testing, and local PBX servers**.

- **Docker Hub:** [hub.docker.com/r/ltfnproject/freepbx](https://hub.docker.com/r/ltfnproject/freepbx)
- **Source Code:** [github.com/ltfnproject/freepbx-docker](https://github.com/ltfnproject/freepbx-docker)
- **Architecture:** `linux/amd64` *(compiled with `--disable BUILD_NATIVE`, safe for desktops, laptops, VirtualBox, VMware, Proxmox, and Linux servers)*

---

## Key Components & Features

| Component | Version | Details |
| :--- | :--- | :--- |
| **Base OS** | Debian 12 Slim (Bookworm) | Debian 12 LTS security patches through June 2028 |
| **Telephony Engine** | Asterisk 22 LTS | PJSIP, `format_mp3`, ODBC CDR (`res_odbc`, `cdr_adaptive_odbc`), SRTP, built-in H.264/VP8 SIP video passthrough, EN ULAW/ALAW sounds & MOH |
| **PBX Web Admin** | FreePBX 17 Stable | 31+ pre-installed modules (`core`, `sipsettings`, `voicemail`, `cdr`, `cel`, `dashboard`, `userman`, `pm2`, `ucp`, `recordings`, `music`, `ivr`, `queues`, `ringgroups`, `callrecording`, `conferences`, `backup`, `soundlang`, `logfiles`, `featurecodeadmin`, `timeconditions`, etc.) |
| **Web & Runtime** | Apache2 + PHP 8.2 + Node.js | Built-in `php.ini` & Apache2 security hardening, automatic PHP `date.timezone` sync |
| **Database** | MariaDB 10.11 (Embedded) | Automatic seeding from `/opt/init` when host volumes are empty |

---

## Available Tags

- `ltfnproject/freepbx:latest` — Latest build from the `main` branch
- `ltfnproject/freepbx:17-ast22` — FreePBX 17 Stable + Asterisk 22 LTS

---

## Quick Start (Docker Compose)

1. Create the project directory and persistent *bind mount* folders:

```bash
mkdir -p freepbx/{data,db,logs}
cd freepbx
```

*(Note: While modern Docker can auto-create missing bind-mount directories, creating them explicitly with `mkdir -p` keeps permissions clean and works consistently across Docker versions.)*

2. Create `docker-compose.yml` inside the `freepbx/` directory:

```yaml
services:
  freepbx:
    image: ltfnproject/freepbx:latest
    container_name: freepbx
    restart: unless-stopped
    ports:
      # Custom Web UI Port (change 8080 as needed)
      - "8080:80"
      # SIP Signaling (PJSIP)
      - "5060:5060/udp"
      - "5060:5060/tcp"
      # Custom RTP Media Port Range (left and right ranges must match)
      - "10000-10100:10000-10100/udp"
    environment:
      - TIMEZONE=Asia/Jakarta
      - DB_EMBEDDED=TRUE
      - RTP_START=10000
      - RTP_FINISH=10100
      - ENABLE_FAIL2BAN=FALSE
      - ENABLE_SSL=FALSE
    volumes:
      - ./data:/data
      - ./db:/var/lib/mysql
      - ./logs:/var/log
```

3. Start the container:

```bash
docker compose up -d
docker compose logs -f freepbx
```

4. Access the FreePBX Web UI in your browser:
   - Open `http://<SERVER-IP>:8080`
   - Create your initial FreePBX Admin account.
   - Navigate to **Settings → Asterisk SIP Settings → General SIP Settings**:
     - Verify **RTP Port Ranges** is automatically configured to `10000` – `10100`.
     - **NAT Configuration (Important for Docker Bridge Mode to avoid *no audio / one-way audio*):**
       - **External Address:** set to the **Docker Host IP** (e.g., `192.168.1.10`).
       - **Local Networks:** include **only the internal Docker subnet** (`172.16.0.0/12`) — do not add your client LAN subnet so Asterisk always advertises the Host IP (instead of internal `172.x.x.x` container IP) in SDP packets to SIP clients.
     - *(Optional — SIP Video Calls)*: Under **Video Codecs**, set **Video Support** to `Enabled` and check `h264` and `vp8`.
     - Click **Submit → Apply Config**, then run `docker compose restart freepbx` once so the updated PJSIP transport takes full effect.

---

## Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `TIMEZONE` | `Asia/Jakarta` | Sets system timezone (`/etc/localtime`) and PHP `date.timezone`. |
| `DB_EMBEDDED` | `TRUE` | Runs embedded MariaDB and auto-seeds initial databases if `./db` is empty. |
| `RTP_START` | `10000` | Lower bound of UDP RTP ports (automatically synced to `kvstore_Sipsettings` & `rtp_additional.conf`). |
| `RTP_FINISH` | `10100` | Upper bound of UDP RTP ports. *(Tip: avoid wide ranges like `10000-20000` in Docker bridge mode as `docker-proxy` consumes heavy RAM; 100 ports support ~50 concurrent audio calls or ~12 video calls.)* |
| `ENABLE_FAIL2BAN` | `FALSE` | Set to `TRUE` to start built-in Fail2Ban *(requires extra network capabilities)*. |
| `ENABLE_SSL` | `FALSE` | Set to `TRUE` to enable Apache2 `default-ssl` HTTPS and PHP `session.cookie_secure`. |

---

## Persistent Volumes (Upgrade-Safe)

| Host Mount | Container Path | Stored Data |
| :--- | :--- | :--- |
| `./data` | `/data` | `/etc/asterisk` configs, voicemail & call recording spool, `/etc/freepbx.conf`, AstDB (`astdb.sqlite3`), TLS `keys`, Music on Hold (`moh`), custom sounds, and backups |
| `./db` | `/var/lib/mysql` | Persistent MariaDB databases (`asterisk` & `asteriskcdrdb`) |
| `./logs` | `/var/log` | Apache2, Asterisk, MariaDB, and Fail2Ban logs |

---

## Quick Verification Commands

```bash
# Check container & healthcheck status
docker ps

# Verify active Asterisk version
docker exec freepbx asterisk -rx "core show version"

# Verify MariaDB ODBC connection for CDR
docker exec freepbx asterisk -rx "odbc show"

# Check PM2 background processes
docker exec freepbx fwconsole pm2 --list

# Attach to Asterisk CLI for live call debugging
docker exec -it freepbx asterisk -rvvv
```

---

## Security Notes

- Uses official **Debian 12 PHP 8.2** packages receiving CVE security backports via `bookworm-security` (supported under Debian 12 LTS through June 2028) along with FreePBX-safe Apache2 and `php.ini` hardening.
- Images are periodically rebuilt to pull upstream OS security updates and verified through automated container smoke tests before publishing.
- Always deploy behind a local firewall or VPN and avoid exposing the Web Admin UI (`8080`) directly to the public internet.
