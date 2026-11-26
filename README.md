# FreePBX 17 + Asterisk 22 LTS + MariaDB (All-in-One Docker)

Image Docker mandiri (*pre-initialized*) **FreePBX 17 Stable + Asterisk 22 LTS + MariaDB** berbasis **Debian 12 (Bookworm)** yang dirancang agar mudah, ringan, dan cepat dijalankan (startup ~10–20 detik) menggunakan `docker-compose.yml` sederhana—ideal untuk **praktikum VoIP / TLJ SMK** maupun deployment server PBX lokal.

- **Docker Hub:** [ltfnproject/freepbx](https://hub.docker.com/r/ltfnproject/freepbx)
- **Source Repository:** [github.com/ltfnproject/freepbx-docker](https://github.com/ltfnproject/freepbx-docker)
- **Arsitektur:** `linux/amd64` (dikompilasi dengan `--disable BUILD_NATIVE`, aman untuk PC lab, VirtualBox, VMware, & Proxmox)

---

## Fitur & Komponen Utama

| Komponen | Versi | Keterangan |
| :--- | :--- | :--- |
| **OS Base** | Debian 12 Slim (Bookworm) | Patch keamanan LTS Debian hingga Juni 2028 |
| **Telephony Engine** | Asterisk 22 LTS | PJSIP, MP3 (`format_mp3`), ODBC CDR, SRTP, suara EN ULAW/ALAW & MOH |
| **Web Admin PBX** | FreePBX 17 Stable | Modul inti & telephony lengkap siap pakai (`core`, `sipsettings`, `voicemail`, `cdr`, `dashboard`, `userman`, `pm2`, `recordings`, `music`, `ivr`, `queues`, `ringgroups`, `timeconditions`, `callrecording`, `soundlang`, `logfiles`, `featurecodeadmin`) |
| **Web & Runtime** | Apache2 + PHP 8.2 + Node.js | Hardening `php.ini` & Apache2 bawaan, kompatibel penuh FreePBX 17 |
| **Database** | MariaDB 10.11 (Embedded) | *Auto-seeding* otomatis dari `/opt/init` saat volume host masih kosong |

---

## Quick Start (Deploy Cepat di Debian Lokal)

1. Buat folder proyek dan file `docker-compose.yml`:

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

2. Jalankan kontainer:

```bash
docker compose up -d
docker compose logs -f freepbx
```

3. Akses Web UI FreePBX di browser:
   - Buka `http://<IP-SERVER-DEBIAN>:8080`
   - Buat akun Admin FreePBX pada halaman awal.
   - Cek **Settings -> Asterisk SIP Settings -> General SIP Settings** -> pastikan **RTP Port Ranges** otomatis bernilai `10000` – `10100`, lalu sesuaikan **Local Networks** / **External Address** sesuai jaringan lab.

---

## Environment Variables

| Variable | Default | Deskripsi |
| :--- | :--- | :--- |
| `TIMEZONE` | `Asia/Jakarta` | Mengatur timezone sistem & `date.timezone` PHP. |
| `DB_EMBEDDED` | `TRUE` | Menjalankan MariaDB internal dan *auto-seeding* jika `./db` masih kosong. |
| `RTP_START` | `10000` | Batas bawah port RTP UDP (disinkronkan ke DB `kvstore_Sipsettings` & `rtp_additional.conf`). |
| `RTP_FINISH` | `10100` | Batas atas port RTP UDP (disarankan rentang 100 port di mode bridge agar RAM `docker-proxy` ringan). |
| `ENABLE_FAIL2BAN` | `FALSE` | Aktifkan `TRUE` jika ingin menjalankan Fail2Ban internal (memerlukan capability jaringan tambahan). |
| `ENABLE_SSL` | `FALSE` | Aktifkan `TRUE` untuk menyalakan HTTPS `default-ssl` Apache2 & cookie PHP `secure`. |

---

## Volume Persisten (Tahan Upgrade Image)

| Mount Host | Path Container | Isi |
| :--- | :--- | :--- |
| `./data` | `/data` | Konfigurasi `/etc/asterisk`, spool voicemail/rekaman, `/etc/freepbx.conf`, AstDB (`astdb.sqlite3`), sertifikat (`keys`), MOH, custom sounds, dan backups |
| `./db` | `/var/lib/mysql` | Database persisten MariaDB (`asterisk` & `asteriskcdrdb`) |
| `./logs` | `/var/log` | Log Apache2, Asterisk, MariaDB, dan Fail2Ban |

---

## Perintah Verifikasi Cepat

```bash
# Cek status health container
docker ps

# Cek versi Asterisk aktif
docker exec freepbx asterisk -rx "core show version"

# Cek koneksi ODBC CDR MariaDB
docker exec freepbx asterisk -rx "odbc show"

# Cek proses PM2
docker exec freepbx fwconsole pm2 --list

# Masuk ke CLI Asterisk
docker exec -it freepbx asterisk -rvvv
```

---

## Catatan Keamanan

- Image ini menggunakan paket **PHP 8.2 resmi Debian 12** yang menerima *security backport* CVE melalui repositori `bookworm-security` (didukung Debian 12 LTS hingga Juni 2028) serta telah dilengkapi *hardening* Apache2 dan `php.ini`.
- Image di-rebuild secara berkala setiap bulan melalui GitHub Actions untuk memasukkan patch keamanan sistem terbaru.
- Untuk deployment produksi maupun lab, letakkan server di balik firewall jaringan lokal dan hindari mengekspos port Web Admin (`8080`) secara langsung ke internet publik tanpa VPN/pembatasan IP.

---

## Panduan Maintainer: Publish Otomatis ke Docker Hub (`ltfnproject/freepbx`)

1. Buat repository publik di GitHub dan push seluruh isi folder ini ke branch `main`.
2. Di Docker Hub (**Account Settings -> Personal Access Tokens**), buat token baru dengan izin **Read & Write**.
3. Di repository GitHub, buka **Settings -> Secrets and variables -> Actions -> New repository secret**, lalu tambahkan:
   - `DOCKERHUB_USERNAME` = `ltfnproject`
   - `DOCKERHUB_TOKEN` = *(token dari langkah 2)*
4. Setiap `git push` ke `main`, pembuatan tag versi (misal `git tag v1.0.0 && git push origin v1.0.0`), atau tombol **Run workflow** di tab **Actions** akan otomatis melakukan **Build -> Trivy Security Scan -> Smoke Test Container -> Push ke `ltfnproject/freepbx` -> Sync README**.
