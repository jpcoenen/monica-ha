#!/bin/bash
# Home Assistant wrapper for the official Monica 4 image.
# 1. Turns /data/options.json into the env vars Monica reads.
# 2. Keeps APP_KEY, HASH_SALT and storage/ in /data so they survive updates.
# 3. Starts the scheduler (reminders) next to Apache.
set -Eeuo pipefail

DATA="${HA_DATA_DIR:-/data}"
OPTIONS="$DATA/options.json"
MONICADIR="${MONICA_DIR:-/var/www/html}"

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
        echo "[ha] Generated $1 (stored in /data, included in add-on backups)" >&2
    fi
    cat "$file"
}

# --- Secrets -----------------------------------------------------------------
APP_KEY="$(persisted app_key 'printf "base64:%s" "$(head -c 32 /dev/urandom | base64)"')"
HASH_SALT="$(persisted hash_salt 'head -c 64 /dev/urandom | base64 | tr -dc "A-Za-z0-9" | head -c 32')"
export APP_KEY HASH_SALT

# --- Configuration -----------------------------------------------------------
export APP_ENV=production
export APP_DEBUG=false
export APP_URL="$(opt app_url)"
export APP_FORCE_URL="$(opt force_url)"
export APP_TRUSTED_PROXIES="$(opt trusted_proxies)"
export APP_DISABLE_SIGNUP="$(opt disable_signup)"

export DB_CONNECTION=mysql
export DB_HOST="$(opt db_host)"
export DB_PORT="$(opt db_port)"
export DB_DATABASE="$(opt db_database)"
export DB_USERNAME="$(opt db_username)"
export DB_PASSWORD="$(opt db_password)"

export MAIL_MAILER="$(opt mail_mailer)"
for key in host port username password encryption from_address from_name; do
    value="$(opt "mail_${key}")"
    if [ -n "$value" ]; then
        export "MAIL_${key^^}=$value"
    fi
done

if [ -z "$DB_PASSWORD" ]; then
    echo "[ha] db_password is empty: set it in the add-on configuration." >&2
    exit 1
fi

# --- Persistent storage --------------------------------------------------------
# storage/ holds uploads, avatars, logs and the OAuth (Passport) keys.
if [ ! -L "$MONICADIR/storage" ]; then
    if [ ! -d "$DATA/storage" ]; then
        echo "[ha] First start: copying storage/ to $DATA/storage"
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
busybox crond -b -l 8 -L /dev/stdout
echo "[ha] Scheduler started"

# --- Hand over to the official entrypoint ------------------------------------------
# It waits for MariaDB, runs migrations (monica:update) and creates Passport keys.
exec "${MONICA_ENTRYPOINT:-/usr/local/bin/entrypoint.sh}" "$@"
