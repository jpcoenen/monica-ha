#!/bin/bash
# Home Assistant wrapper for the official Monica 4 image, with a bundled MariaDB.
# 1. Turns /data/options.json into the env vars Monica reads.
# 2. Keeps the database, storage/ and generated secrets in /data.
# 3. Runs MariaDB, the scheduler (reminders) and Apache, and stops them cleanly.
set -Eeuo pipefail

DATA="${HA_DATA_DIR:-/data}"
OPTIONS="$DATA/options.json"
MONICADIR="${MONICA_DIR:-/var/www/html}"
DB_DATADIR="$DATA/mysql"
DB_RUNDIR=/run/mysqld
DB_SOCKET="$DB_RUNDIR/mysqld.sock"

log() { echo "[ha] $*" >&2; }

# Read one option; booleans become "true"/"false", missing optional keys "".
opt() {
    php -r '
        $o = json_decode(file_get_contents($argv[1]), true);
        $v = $o[$argv[2]] ?? "";
        if (is_bool($v)) { $v = $v ? "true" : "false"; }
        echo $v;
    ' -- "$OPTIONS" "$1"
}

# Generate a secret once and keep it in /data.
persisted() {
    local file="$DATA/$1"
    if [ ! -s "$file" ]; then
        eval "$2" > "$file"
        chmod 600 "$file"
        log "Generated $1 (stored in /data, included in add-on backups)"
    fi
    cat "$file"
}

random_alnum() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

# --- Secrets -----------------------------------------------------------------
APP_KEY="$(persisted app_key 'printf "base64:%s" "$(head -c 32 /dev/urandom | base64)"')"
HASH_SALT="$(persisted hash_salt 'random_alnum 32')"
DB_PASSWORD="$(persisted db_password 'random_alnum 32')"
export APP_KEY HASH_SALT DB_PASSWORD

# --- Configuration -----------------------------------------------------------
export APP_ENV=production
export APP_DEBUG=false
export APP_URL="$(opt app_url)"
export APP_FORCE_URL="$(opt force_url)"
export APP_TRUSTED_PROXIES="$(opt trusted_proxies)"
export APP_DISABLE_SIGNUP="$(opt disable_signup)"

# Send Monica's own errors to the add-on log instead of a file in /data.
export LOG_CHANNEL=stderr

# The bundled MariaDB listens on a socket only (no network port).
export DB_CONNECTION=mysql
export DB_HOST=localhost
export DB_PORT=3306
export DB_UNIX_SOCKET="$DB_SOCKET"
export DB_DATABASE=monica
export DB_USERNAME=monica

export MAIL_MAILER="$(opt mail_mailer)"
for key in host port username password encryption from_address from_name; do
    value="$(opt "mail_${key}")"
    if [ -n "$value" ]; then
        export "MAIL_${key^^}=$value"
    fi
done

# --- MariaDB -------------------------------------------------------------------
mkdir -p "$DB_RUNDIR" "$DB_DATADIR"
chown mysql:mysql "$DB_RUNDIR" "$DB_DATADIR"

if [ ! -d "$DB_DATADIR/mysql" ]; then
    log "First start: creating the database in $DB_DATADIR"
    mariadb-install-db --user=mysql --datadir="$DB_DATADIR" \
        --auth-root-authentication-method=socket --skip-test-db >/dev/null
fi

mariadbd --user=mysql --datadir="$DB_DATADIR" \
    --socket="$DB_SOCKET" --pid-file="$DB_RUNDIR/mysqld.pid" \
    --skip-networking --skip-name-resolve \
    --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci \
    --innodb-buffer-pool-size=64M --log-warnings=1 &
DB_PID=$!

for _ in $(seq 1 60); do
    if mariadb-admin --socket="$DB_SOCKET" -uroot ping --silent 2>/dev/null; then
        break
    fi
    if ! kill -0 "$DB_PID" 2>/dev/null; then
        log "MariaDB failed to start; see the lines above."
        exit 1
    fi
    sleep 1
done
log "MariaDB ready"

# After an add-on update with a newer MariaDB; a no-op otherwise.
mariadb-upgrade --socket="$DB_SOCKET" -uroot --silent >/dev/null 2>&1 || true

# Idempotent: also re-applies the password if /data/db_password changed.
mariadb --socket="$DB_SOCKET" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS monica CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'monica'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER 'monica'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON monica.* TO 'monica'@'localhost';
SQL

APP_PID=""
CRON_PID=""
stop_all() {
    trap - TERM INT
    log "Stopping Monica and MariaDB"
    for pid in "$APP_PID" "$CRON_PID"; do
        if [ -n "$pid" ]; then
            kill -TERM "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
    mariadb-admin --socket="$DB_SOCKET" -uroot shutdown 2>/dev/null || kill -TERM "$DB_PID" 2>/dev/null || true
    wait "$DB_PID" 2>/dev/null || true
}
trap 'stop_all; exit 0' TERM INT

# --- Persistent storage --------------------------------------------------------
# storage/ holds uploads, avatars, logs and the OAuth (Passport) keys.
if [ ! -L "$MONICADIR/storage" ]; then
    if [ ! -d "$DATA/storage" ]; then
        log "First start: copying storage/ to $DATA/storage"
        cp -a "$MONICADIR/storage" "$DATA/storage"
    fi
    rm -rf "$MONICADIR/storage"
    ln -s "$DATA/storage" "$MONICADIR/storage"
fi
mkdir -p "$DATA/storage/app/public"
chown -R www-data:www-data "$DATA/storage"

# --- Scheduler -----------------------------------------------------------------
# The image ships a www-data crontab running `artisan schedule:run` every minute.
# busybox crond passes its environment on to the jobs, so they see the vars above.
busybox crond -f -l 8 -L /dev/stdout &
CRON_PID=$!
log "Scheduler started"

# --- Monica ----------------------------------------------------------------------
# The official entrypoint waits for the database, runs migrations (monica:update),
# creates the Passport keys and then starts Apache. monica:update runs
# `php artisan` relative to the working directory, so start from Monica's folder.
cd "$MONICADIR"
"${MONICA_ENTRYPOINT:-/usr/local/bin/entrypoint.sh}" "$@" &
APP_PID=$!

code=0
wait "$APP_PID" || code=$?
log "Monica exited with code $code"
APP_PID=""
stop_all
exit "$code"
