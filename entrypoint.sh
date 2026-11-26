#!/usr/bin/env bash
set -euo pipefail

TIMEZONE="${TIMEZONE:-Asia/Jakarta}"
DB_EMBEDDED="${DB_EMBEDDED:-TRUE}"
RTP_START="${RTP_START:-10000}"
RTP_FINISH="${RTP_FINISH:-10100}"
ENABLE_FAIL2BAN="${ENABLE_FAIL2BAN:-FALSE}"
ENABLE_SSL="${ENABLE_SSL:-FALSE}"

# Validasi rentang port RTP agar selalu numerik dan valid
if ! [[ "${RTP_START}" =~ ^[0-9]+$ ]] || ! [[ "${RTP_FINISH}" =~ ^[0-9]+$ ]] || [ "${RTP_START}" -ge "${RTP_FINISH}" ]; then
    echo "[ERROR] RTP_START (${RTP_START}) dan RTP_FINISH (${RTP_FINISH}) harus berupa angka valid dengan RTP_START < RTP_FINISH." >&2
    exit 1
fi

# 1. Atur Timezone sistem & PHP
if [ -f "/usr/share/zoneinfo/${TIMEZONE}" ]; then
    ln -snf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
    printf "date.timezone = %s\n" "${TIMEZONE}" > /etc/php/8.2/apache2/conf.d/99-timezone.ini
    printf "date.timezone = %s\n" "${TIMEZONE}" > /etc/php/8.2/cli/conf.d/99-timezone.ini
fi

# 2. Pastikan struktur folder log & runtime tersedia (penting saat ./logs:/var/log di-mount kosong)
mkdir -p /var/log/apache2 /var/log/asterisk /var/log/mysql /var/log/fail2ban \
         /run/mysqld /var/run/asterisk /var/run/apache2 /var/lock/apache2 /home/asterisk
chown -R asterisk:asterisk /var/log/asterisk /var/run/asterisk /var/run/apache2 /var/lock/apache2 /home/asterisk
chown -R mysql:mysql /var/log/mysql /run/mysqld
chown -R asterisk:adm /var/log/apache2

# Helper: auto-seed direktori kosong & buat symlink ke /data
seed_and_link_dir() {
    local init_src="$1"
    local data_dst="$2"
    local sys_link="$3"

    mkdir -p "${data_dst}"
    if [ -z "$(ls -A "${data_dst}")" ] && [ -d "${init_src}" ]; then
        cp -a "${init_src}/." "${data_dst}/"
    fi
    rm -rf "${sys_link}"
    ln -s "${data_dst}" "${sys_link}"
}

# 3. Sinkronisasi data persisten ke /data (tahan upgrade image)
mkdir -p /data/backups /data/astdb

seed_and_link_dir "/opt/init/etc-asterisk" "/data/etc-asterisk" "/etc/asterisk"
seed_and_link_dir "/opt/init/spool-asterisk" "/data/spool-asterisk" "/var/spool/asterisk"
seed_and_link_dir "/opt/init/keys" "/data/keys" "/var/lib/asterisk/keys"
seed_and_link_dir "/opt/init/moh" "/data/moh" "/var/lib/asterisk/moh"
seed_and_link_dir "/opt/init/sounds-custom" "/data/sounds-custom" "/var/lib/asterisk/sounds/custom"

# Persist /etc/freepbx.conf agar password DB tetap cocok setelah upgrade image baru
if [ ! -f "/data/freepbx.conf" ] && [ -f "/opt/init/freepbx.conf" ]; then
    cp -a /opt/init/freepbx.conf /data/freepbx.conf
fi
rm -f /etc/freepbx.conf
ln -s /data/freepbx.conf /etc/freepbx.conf

# Persist AstDB (/data/astdb/astdb.sqlite3) & pastikan asterisk.conf menunjuk ke /data/astdb
if [ ! -f "/data/astdb/astdb.sqlite3" ] && [ -f "/opt/init/astdb/astdb.sqlite3" ]; then
    cp -a /opt/init/astdb/astdb.sqlite3 /data/astdb/astdb.sqlite3
fi
if [ -f "/data/etc-asterisk/asterisk.conf" ]; then
    if grep -Eq '^[[:space:]]*astdbdir' /data/etc-asterisk/asterisk.conf; then
        sed -i 's|^[[:space:]]*astdbdir.*|astdbdir => /data/astdb|' /data/etc-asterisk/asterisk.conf
    else
        sed -i '/^\[directories\]/a astdbdir => /data/astdb' /data/etc-asterisk/asterisk.conf
    fi
fi

chown -R asterisk:asterisk /data/etc-asterisk /data/spool-asterisk /data/backups \
                           /data/astdb /data/keys /data/moh /data/sounds-custom
chown asterisk:asterisk /data/freepbx.conf
chmod 640 /data/freepbx.conf

# 4. Inisialisasi & jalankan MariaDB internal jika DB_EMBEDDED=TRUE
if [ "${DB_EMBEDDED^^}" = "TRUE" ]; then
    mkdir -p /var/lib/mysql
    if [ ! -d "/var/lib/mysql/asterisk" ]; then
        echo "[INIT] Mengisi database awal MariaDB ke /var/lib/mysql..."
        cp -a /opt/init/mysql/. /var/lib/mysql/
    fi
    chown -R mysql:mysql /var/lib/mysql
    service mariadb start
    for i in $(seq 1 60); do
        if mysqladmin ping --silent; then
            break
        fi
        sleep 1
    done
    if ! mysqladmin ping --silent; then
        echo "[ERROR] MariaDB gagal menyala dalam 60 detik." >&2
        exit 1
    fi
fi

# 5. Terapkan rentang RTP custom ke database FreePBX (UPSERT) & rtp_additional.conf
if [ "${DB_EMBEDDED^^}" = "TRUE" ]; then
    mysql asterisk -e "
        INSERT INTO kvstore_Sipsettings (\`key\`, \`val\`, \`type\`, \`id\`)
        VALUES ('rtpstart', '${RTP_START}', NULL, 'noid')
        ON DUPLICATE KEY UPDATE val='${RTP_START}', type=NULL;
        INSERT INTO kvstore_Sipsettings (\`key\`, \`val\`, \`type\`, \`id\`)
        VALUES ('rtpend', '${RTP_FINISH}', NULL, 'noid')
        ON DUPLICATE KEY UPDATE val='${RTP_FINISH}', type=NULL;
    " || echo "[WARN] Gagal memperbarui kvstore_Sipsettings, akan menggunakan fallback file konfigurasi."
fi

if [ -f /etc/asterisk/rtp_additional.conf ]; then
    sed -i -E "s/^[[:space:]]*rtpstart[[:space:]]*=.*/rtpstart=${RTP_START}/" /etc/asterisk/rtp_additional.conf || true
    sed -i -E "s/^[[:space:]]*rtpend[[:space:]]*=.*/rtpend=${RTP_FINISH}/" /etc/asterisk/rtp_additional.conf || true
fi

# 6. Konfigurasi SSL & Fail2Ban opsional
if [ "${ENABLE_SSL^^}" = "TRUE" ]; then
    a2enmod ssl >/dev/null 2>&1 || true
    a2ensite default-ssl >/dev/null 2>&1 || true
    printf "session.cookie_secure = 1\n" > /etc/php/8.2/apache2/conf.d/99-freepbx-ssl.ini
else
    rm -f /etc/php/8.2/apache2/conf.d/99-freepbx-ssl.ini
fi

if [ "${ENABLE_FAIL2BAN^^}" = "TRUE" ]; then
    service fail2ban start || true
fi

# 7. Jalankan cron dan FreePBX + Asterisk
service cron start
fwconsole start
fwconsole reload || true

# Pastikan rtp_additional.conf tetap sinkron setelah reload
if [ -f /etc/asterisk/rtp_additional.conf ]; then
    sed -i -E "s/^[[:space:]]*rtpstart[[:space:]]*=.*/rtpstart=${RTP_START}/" /etc/asterisk/rtp_additional.conf || true
    sed -i -E "s/^[[:space:]]*rtpend[[:space:]]*=.*/rtpend=${RTP_FINISH}/" /etc/asterisk/rtp_additional.conf || true
    asterisk -rx "module reload res_rtp_asterisk.so" >/dev/null 2>&1 || true
fi

# 8. Tangkap sinyal stop agar Apache, Asterisk, dan MariaDB mati dengan aman
shutdown_handler() {
    echo "[STOP] Menghentikan Apache, Asterisk, dan MariaDB dengan aman..."
    apache2ctl -k graceful-stop || true
    fwconsole stop || true
    if [ "${DB_EMBEDDED^^}" = "TRUE" ]; then
        service mariadb stop || true
    fi
    exit 0
}
trap shutdown_handler SIGTERM SIGINT

echo "[READY] FreePBX 17 + Asterisk 22 LTS siap digunakan (RTP: ${RTP_START}-${RTP_FINISH})."

# 9. Jalankan Apache di foreground
apache2ctl -D FOREGROUND &
APACHE_PID=$!
wait "${APACHE_PID}"
