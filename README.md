# FreePBX 17 + Asterisk 22 LTS + MariaDB (All-in-One Docker)

[![Build, Test, and Publish](https://github.com/ltfnproject/freepbx-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/ltfnproject/freepbx-docker/actions/workflows/docker-publish.yml)
[![Docker Hub](https://img.shields.io/docker/v/ltfnproject/freepbx?sort=semver&label=Docker%20Hub)](https://hub.docker.com/r/ltfnproject/freepbx)
[![Docker Image Size](https://img.shields.io/docker/image-size/ltfnproject/freepbx/latest)](https://hub.docker.com/r/ltfnproject/freepbx)

Image Docker mandiri (*pre-initialized*) **FreePBX 17 Stable + Asterisk 22 LTS + MariaDB (embedded)** berbasis **Debian 12 (Bookworm)** yang siap pakai dan ringan (~486 MB terkompresi). Dirancang agar mudah dijalankan dengan satu file `docker-compose.yml` sederhana dan waktu startup cepat (**~10–20 detik**) tanpa menunggu instalasi modul/database saat *first boot*—cocok untuk **praktikum VoIP / jaringan, lab simulasi, maupun server PBX lokal**.

- **Docker Hub:** [hub.docker.com/r/ltfnproject/freepbx](https://hub.docker.com/r/ltfnproject/freepbx)
- **Source Code:** [github.com/ltfnproject/freepbx-docker](https://github.com/ltfnproject/freepbx-docker)
- **Arsitektur:** `linux/amd64` *(dikompilasi dengan `--disable BUILD_NATIVE`, kompatibel untuk PC, laptop, VirtualBox, VMware, Proxmox, dan server Linux)*

---

## Komponen & Fitur Utama

| Komponen | Versi | Keterangan |
| :--- | :--- | :--- |
| **Base OS** | Debian 12 Slim (Bookworm) | Patch keamanan LTS Debian hingga Juni 2028 |
| **Telephony Engine** | Asterisk 22 LTS | PJSIP, `format_mp3`, ODBC CDR (`res_odbc`, `cdr_adaptive_odbc`), SRTP, suara EN ULAW/ALAW & MOH |
| **Web Admin PBX** | FreePBX 17 Stable | 31+ modul siap pakai (`core`, `sipsettings`, `voicemail`, `cdr`, `cel`, `dashboard`, `userman`, `pm2`, `ucp`, `recordings`, `music`, `ivr`, `queues`, `ringgroups`, `callrecording`, `conferences`, `backup`, `soundlang`, `logfiles`, `featurecodeadmin`, `timeconditions`, dll.) |
| **Web & Runtime** | Apache2 + PHP 8.2 + Node.js | Hardening `php.ini` & Apache2 bawaan, sinkronisasi `date.timezone` otomatis |
| **Database** | MariaDB 10.11 (Embedded) | *Auto-seeding* otomatis dari `/opt/init` saat volume host masih kosong |

---

## Tag yang Tersedia

- `ltfnproject/freepbx:latest` — Rilis terbaru dari branch `main`
- `ltfnproject/freepbx:17-ast22` — FreePBX 17 Stable + Asterisk 22 LTS

---

## Quick Start (Docker Compose)

1. Buat direktori proyek beserta folder volume (*bind mount*) untuk data persisten:

```bash
mkdir -p freepbx/{data,db,logs}
cd freepbx
```

*(Catatan: Meskipun Docker modern bisa membuat folder bind mount secara otomatis, membuatnya terlebih dahulu dengan `mkdir -p` disarankan agar struktur folder rapi dan kompatibel di semua versi Docker.)*

2. Buat file `docker-compose.yml` di dalam folder `freepbx/`:

```yaml
services:
  freepbx:
    image: ltfnproject/freepbx:latest
    container_name: freepbx
    restart: unless-stopped
    ports:
      # Custom Port Web UI (ubah 8080 sesuai kebutuhan)
      - "8080:80"
      # Port SIP (PJSIP)
      - "5060:5060/udp"
      - "5060:5060/tcp"
      # Custom Rentang Port RTP (angka kiri & kanan wajib sama persis)
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

3. Jalankan kontainer:

```bash
docker compose up -d
docker compose logs -f freepbx
```

4. Akses Web UI FreePBX di browser:
   - Buka `http://<IP-SERVER>:8080`
   - Buat akun Admin FreePBX pada halaman *initial setup*.
   - Masuk ke **Settings → Asterisk SIP Settings → General SIP Settings**:
     - Pastikan **RTP Port Ranges** otomatis bernilai `10000` – `10100`.
     - Sesuaikan **Local Networks** dan **External Address** sesuai topologi jaringan Anda.

---

## Environment Variables

| Variable | Default | Deskripsi |
| :--- | :--- | :--- |
| `TIMEZONE` | `Asia/Jakarta` | Mengatur timezone sistem (`/etc/localtime`) dan `date.timezone` PHP. |
| `DB_EMBEDDED` | `TRUE` | Menjalankan MariaDB internal dan *auto-seeding* otomatis bila `./db` masih kosong. |
| `RTP_START` | `10000` | Batas bawah port RTP UDP (disinkronkan otomatis ke `kvstore_Sipsettings` & `rtp_additional.conf`). |
| `RTP_FINISH` | `10100` | Batas atas port RTP UDP. *(Tips: hindari rentang terlalu lebar seperti `10000-20000` pada Docker mode bridge karena `docker-proxy` akan memakan RAM besar; rentang 100 port cukup untuk ±50 panggilan bersamaan.)* |
| `ENABLE_FAIL2BAN` | `FALSE` | Ubah ke `TRUE` untuk menyalakan Fail2Ban internal *(membutuhkan capability jaringan tambahan)*. |
| `ENABLE_SSL` | `FALSE` | Ubah ke `TRUE` untuk mengaktifkan HTTPS `default-ssl` Apache2 & cookie PHP `secure`. |

---

## Volume Persisten (Aman Saat Upgrade Image)

| Mount Host | Path Container | Data yang Disimpan |
| :--- | :--- | :--- |
| `./data` | `/data` | Konfigurasi `/etc/asterisk`, spool voicemail & rekaman, `/etc/freepbx.conf`, AstDB (`astdb.sqlite3`), sertifikat (`keys`), *Music on Hold* (`moh`), *custom sounds*, dan *backups* |
| `./db` | `/var/lib/mysql` | Database persisten MariaDB (`asterisk` & `asteriskcdrdb`) |
| `./logs` | `/var/log` | Log Apache2, Asterisk, MariaDB, dan Fail2Ban |

---

## Perintah Verifikasi Cepat

```bash
# Cek status container & healthcheck
docker ps

# Cek versi Asterisk aktif
docker exec freepbx asterisk -rx "core show version"

# Cek koneksi ODBC CDR ke MariaDB
docker exec freepbx asterisk -rx "odbc show"

# Cek layanan PM2
docker exec freepbx fwconsole pm2 --list

# Masuk ke CLI Asterisk untuk monitoring panggilan
docker exec -it freepbx asterisk -rvvv
```

---

## Catatan Keamanan

- Menggunakan paket **PHP 8.2 resmi Debian 12** yang menerima *security backport* CVE dari repositori `bookworm-security` (didukung Debian 12 LTS hingga Juni 2028) serta telah dilengkapi *hardening* Apache2 dan `php.ini`.
- Image diperbarui secara berkala untuk menyertakan patch keamanan sistem terbaru dan diverifikasi dengan *automated smoke test* sebelum dirilis.
- Disarankan menjalankan server PBX di balik firewall jaringan lokal/VPN dan tidak mengekspos port Web Admin (`8080`) secara terbuka ke internet publik.
