# ==============================================================================
# Stage 1: Asterisk 22 LTS Builder (Debian 12 Bookworm)
# ==============================================================================
FROM debian:12-slim AS asterisk-builder

ARG ASTERISK_MAJOR=22
ENV DEBIAN_FRONTEND=noninteractive

# Pasang toolchain & library dev untuk kompilasi Asterisk 22 LTS (termasuk ODBC, cURL, SRTP)
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    build-essential pkg-config ca-certificates curl wget subversion bzip2 patch file \
    bison flex \
    uuid-dev libxml2-dev libsqlite3-dev libssl-dev libjansson-dev \
    libedit-dev libncurses-dev libnewt-dev \
    unixodbc-dev libcurl4-openssl-dev libsrtp2-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# Unduh source Asterisk 22 LTS terbaru (dengan timeout & retry agar tidak hang jika mirror lambat)
RUN curl -4 -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 30 --max-time 300 \
        --retry 4 --retry-delay 5 --retry-all-errors \
        "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_MAJOR}-current.tar.gz" \
        -o asterisk.tar.gz \
    && mkdir -p /usr/src/asterisk \
    && tar xzf asterisk.tar.gz --strip-components=1 -C /usr/src/asterisk \
    && rm -f asterisk.tar.gz

# Kompilasi & install ke staging directory (DESTDIR)
# Catatan:
# - --disable BUILD_NATIVE WAJIB agar binary kompatibel di semua CPU x86_64 (PC lab / VM Proxmox / VirtualBox)
# - app_macro sudah dihapus sejak Asterisk 21 (FreePBX 17 menggunakan Gosub)
WORKDIR /usr/src/asterisk
RUN set -eux; \
    contrib/scripts/get_mp3_source.sh; \
    ./configure --with-pjproject-bundled --with-jansson-bundled --libdir=/usr/lib; \
    make menuselect.makeopts; \
    menuselect/menuselect \
        --disable BUILD_NATIVE \
        --enable format_mp3 \
        --enable res_odbc \
        --enable cdr_adaptive_odbc \
        --enable func_odbc \
        --enable CORE-SOUNDS-EN-ULAW \
        --enable CORE-SOUNDS-EN-ALAW \
        --enable MOH-OPSOUND-WAV \
        menuselect.makeopts; \
    make -j"$(nproc)"; \
    mkdir -p /tmp/asterisk-install; \
    make DESTDIR=/tmp/asterisk-install install; \
    make DESTDIR=/tmp/asterisk-install samples; \
    mkdir -p /tmp/asterisk-install/var/log/asterisk /tmp/asterisk-install/var/spool/asterisk /tmp/asterisk-install/var/lib/asterisk; \
    rm -rf /tmp/asterisk-install/var/run; \
    test -f /tmp/asterisk-install/usr/lib/asterisk/modules/format_mp3.so; \
    test -f /tmp/asterisk-install/usr/lib/asterisk/modules/res_odbc.so; \
    test -f /tmp/asterisk-install/usr/lib/asterisk/modules/cdr_adaptive_odbc.so; \
    test -f /tmp/asterisk-install/usr/lib/asterisk/modules/func_odbc.so


# ==============================================================================
# Stage 2: Runtime All-in-One FreePBX 17 Stable + Asterisk 22 LTS + MariaDB
# ==============================================================================
FROM debian:12-slim AS runtime

ARG FREEPBX_URL=https://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz

LABEL org.opencontainers.image.title="FreePBX 17 + Asterisk 22 LTS + MariaDB (All-in-One)" \
      org.opencontainers.image.description="Pre-initialized All-in-One FreePBX 17 Stable + Asterisk 22 LTS + Embedded MariaDB on Debian 12" \
      org.opencontainers.image.source="https://github.com/ltfnproject/freepbx-docker" \
      org.opencontainers.image.vendor="ltfnproject"

ENV DEBIAN_FRONTEND=noninteractive

# 1. Pasang security patch Debian 12 terbaru + paket runtime (tanpa build-essential & tanpa ffmpeg)
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    apache2 libapache2-mod-php8.2 \
    mariadb-server mariadb-client \
    php8.2 php8.2-cli php8.2-common php8.2-curl php8.2-gd php8.2-intl \
    php8.2-mbstring php8.2-mysql php8.2-xml php8.2-zip php8.2-bcmath \
    php8.2-ldap php8.2-soap php8.2-sqlite3 \
    nodejs npm cron fail2ban \
    unixodbc odbc-mariadb libodbc2 \
    sox libsox-fmt-mp3 mpg123 lame sqlite3 \
    curl wget ca-certificates gnupg dirmngr tzdata procps sudo iproute2 \
    libssl3 libxml2 libsqlite3-0 libjansson4 libedit2 libncurses6 \
    libuuid1 libcurl4 libsrtp2-1 libnewt0.52 \
    && rm -rf /var/lib/apt/lists/*

# 2. Buat user & home directory asterisk (penting untuk PM2 dan Apache)
RUN useradd -m -d /home/asterisk -s /bin/bash asterisk

# 3. Salin hasil kompilasi Asterisk 22 LTS dari Stage 1 (salin direktori spesifik agar tidak menimpa symlink /var/run -> /run)
COPY --from=asterisk-builder /tmp/asterisk-install/usr /usr
COPY --from=asterisk-builder /tmp/asterisk-install/etc/asterisk /etc/asterisk
COPY --from=asterisk-builder /tmp/asterisk-install/var/lib/asterisk /var/lib/asterisk
COPY --from=asterisk-builder /tmp/asterisk-install/var/spool/asterisk /var/spool/asterisk
COPY --from=asterisk-builder /tmp/asterisk-install/var/log/asterisk /var/log/asterisk
RUN ldconfig \
    && asterisk -V \
    && mkdir -p /run/asterisk /var/log/asterisk /var/spool/asterisk \
                /var/lib/asterisk/sounds/custom /var/lib/asterisk/keys /var/lib/asterisk/moh \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk /var/log/asterisk \
                /var/spool/asterisk /run/asterisk /usr/lib/asterisk /home/asterisk

# 4. Konfigurasi & Hardening Apache2 + PHP 8.2 (kompatibel penuh dengan FreePBX 17)
RUN set -eux; \
    sed -i 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=asterisk/' /etc/apache2/envvars; \
    sed -i 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=asterisk/' /etc/apache2/envvars; \
    sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf; \
    printf "ServerName localhost\nServerTokens Prod\nServerSignature Off\nTraceEnable Off\n" \
        > /etc/apache2/conf-available/security-hardening.conf; \
    a2enconf security-hardening; \
    a2enmod rewrite headers; \
    rm -f /var/www/html/index.html; \
    mkdir -p /var/run/apache2 /var/lock/apache2 /var/log/apache2; \
    chown -R asterisk:asterisk /var/www/html /var/run/apache2 /var/lock/apache2; \
    chown -R asterisk:adm /var/log/apache2; \
    printf '%s\n' \
        '; FreePBX 17 Resource Limits' \
        'upload_max_filesize = 128M' \
        'post_max_size = 128M' \
        'memory_limit = 512M' \
        'max_execution_time = 300' \
        'max_input_vars = 5000' \
        '' \
        '; PHP 8.2 Security Hardening (FreePBX-compatible)' \
        'expose_php = Off' \
        'display_errors = Off' \
        'display_startup_errors = Off' \
        'log_errors = On' \
        'allow_url_include = Off' \
        'session.use_strict_mode = 1' \
        'session.cookie_httponly = 1' \
        'session.cookie_samesite = Lax' \
        > /etc/php/8.2/apache2/conf.d/99-freepbx.ini; \
    cp /etc/php/8.2/apache2/conf.d/99-freepbx.ini /etc/php/8.2/cli/conf.d/99-freepbx.ini

# 5. Konfigurasi ODBC MariaDB untuk CDR Asterisk
RUN set -eux; \
    DRIVER_PATH="$(find /usr/lib -name 'libmaodbc.so' | head -n 1)"; \
    test -n "${DRIVER_PATH}"; \
    printf "[MySQL]\nDescription=ODBC for MySQL (MariaDB)\nDriver=%s\nSetup=%s\nFileUsage=1\n" \
        "${DRIVER_PATH}" "${DRIVER_PATH}" > /etc/odbcinst.ini; \
    printf "[MySQL-asteriskcdrdb]\nDescription=MySQL connection to asteriskcdrdb\nDriver=MySQL\nServer=localhost\nDatabase=asteriskcdrdb\nPort=3306\nSocket=/run/mysqld/mysqld.sock\nOption=3\n" \
        > /etc/odbc.ini

# 6. Unduh & instal FreePBX 17 Stable + modul lengkap + pindahkan state awal ke /opt/init dalam satu layer
# Catatan: build-essential & git dipasang sementara agar modul node-gyp (ucp/pm2) terinstal mulus, lalu dihapus di layer yang sama
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential git; \
    curl -4 -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 30 --max-time 240 \
        --retry 3 --retry-delay 5 --retry-all-errors "${FREEPBX_URL}" -o /tmp/freepbx.tgz \
    || curl -4 -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 30 --max-time 240 \
        --retry 3 --retry-delay 5 --retry-all-errors \
        "https://mirror1.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz" -o /tmp/freepbx.tgz \
    || curl -4 -fsSL --connect-timeout 20 --speed-limit 1024 --speed-time 30 --max-time 240 \
        --retry 3 --retry-delay 5 --retry-all-errors \
        "http://mirror2.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest.tgz" -o /tmp/freepbx.tgz; \
    mkdir -p /usr/src/freepbx; \
    tar xzf /tmp/freepbx.tgz --strip-components=1 -C /usr/src/freepbx; \
    rm -f /tmp/freepbx.tgz; \
    mkdir -p /run/mysqld; \
    chown -R mysql:mysql /run/mysqld /var/lib/mysql; \
    service mariadb start; \
    for i in $(seq 1 30); do mysqladmin ping --silent && break; sleep 1; done; \
    cd /usr/src/freepbx; \
    ./start_asterisk start; \
    for i in $(seq 1 30); do asterisk -rx "core show version" >/dev/null 2>&1 && break; sleep 1; done; \
    ./install -n; \
    fwconsole ma disablerepo commercial || true; \
    fwconsole chown; \
    fwconsole ma downloadinstall core sipsettings voicemail cdr dashboard userman pm2; \
    fwconsole ma downloadinstall soundlang logfiles featurecodeadmin recordings music; \
    fwconsole ma downloadinstall callrecording ivr queues ringgroups timeconditions; \
    fwconsole chown; \
    fwconsole reload; \
    fwconsole stop; \
    service mariadb stop; \
    mkdir -p /opt/init/astdb; \
    if [ -f /var/lib/asterisk/astdb.sqlite3 ]; then \
        mv /var/lib/asterisk/astdb.sqlite3 /opt/init/astdb/astdb.sqlite3; \
    fi; \
    if grep -Eq '^[[:space:]]*astdbdir' /etc/asterisk/asterisk.conf; then \
        sed -i 's|^[[:space:]]*astdbdir.*|astdbdir => /data/astdb|' /etc/asterisk/asterisk.conf; \
    else \
        sed -i '/^\[directories\]/a astdbdir => /data/astdb' /etc/asterisk/asterisk.conf; \
    fi; \
    mv /var/lib/mysql /opt/init/mysql; \
    mv /etc/asterisk /opt/init/etc-asterisk; \
    mv /var/spool/asterisk /opt/init/spool-asterisk; \
    mv /etc/freepbx.conf /opt/init/freepbx.conf; \
    mv /var/lib/asterisk/keys /opt/init/keys; \
    mv /var/lib/asterisk/moh /opt/init/moh; \
    mv /var/lib/asterisk/sounds/custom /opt/init/sounds-custom; \
    mkdir -p /var/lib/mysql /etc/asterisk /var/spool/asterisk \
             /var/lib/asterisk/keys /var/lib/asterisk/moh /var/lib/asterisk/sounds/custom; \
    apt-get purge -y --auto-remove build-essential git; \
    asterisk -V; \
    rm -rf /var/lib/apt/lists/* /usr/src/freepbx /tmp/* /var/tmp/* /root/.npm /home/asterisk/.npm \
           /var/log/asterisk/* /var/log/mysql/* /var/log/apache2/*

# 7. Pasang skrip entrypoint dengan jaminan line ending LF
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 80 443 5060/udp 5060/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fsS http://127.0.0.1/ >/dev/null && asterisk -rx "core show uptime" >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
