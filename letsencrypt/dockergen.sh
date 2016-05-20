#!/bin/bash -e

# Is Let's encrypt feature enabled?
if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  exit 0
fi

export XDG_DATA_HOME=/letsencrypt/data

mkdir -p /ssl/letsencrypt

# List of hosts with Let's encrypt enabled.
HOSTS="$(cat /ssl/letsencrypt.list)"

# Make sure HTTP server can access webroot even if /ssl is otherwise closed.
chmod +001 /ssl /ssl/webroot
for host in $HOSTS; do
  mkdir -p "/ssl/webroot/${host}"

  /letsencrypt/data/letsencrypt/bin/letsencrypt --no-self-upgrade --noninteractive --quiet --agree-tos --email "${LETSENCRYPT_EMAIL}" \
   --config-dir /ssl/letsencrypt certonly --webroot --keep-until-expiring --rsa-key-size 4096 \
   --webroot-path "/ssl/webroot/${host}" --domain "${host}"

  if [ ! -e "/ssl/letsencrypt/live/${host}/privkey.pem" ]; then
    echo "File '/ssl/letsencrypt/live/${host}/privkey.pem' is missing."
    exit 1
  fi
  if [ ! -e "/ssl/letsencrypt/live/${host}/fullchain.pem" ]; then
    echo "File '/ssl/letsencrypt/live/${host}/fullchain.pem' is missing."
    exit 1
  fi

  if [ -e "/ssl/${host}.key" ] && [ ! -L "/ssl/${host}.key" ]; then
    echo "File '/ssl/${host}.key' already exists and it is not a symlink."
    exit 1
  fi
  if [ -e "/ssl/${host}.crt" ] && [ ! -L "/ssl/${host}.crt" ]; then
    echo "File '/ssl/${host}.crt' already exists and it is not a symlink."
    exit 1
  fi

  ln -f -s "letsencrypt/live/${host}/privkey.pem" "/ssl/${host}.key"
  ln -f -s "letsencrypt/live/${host}/fullchain.pem" "/ssl/${host}.crt"
done

EXISTING_HOSTS="$(find /ssl -maxdepth 1 -lname 'letsencrypt*' -printf '%f\n' | rev | cut --fields=2- --delimiter '.' | rev | sort --unique)"

for host in $EXISTING_HOSTS; do
  if ! echo "${HOSTS}" | grep --quiet --line-regexp --fixed-strings "${host}"; then
    # We make sure we are removing only symlinks.
    if [ -L "/ssl/${host}.key" ]; then
      rm -f "/ssl/${host}.key"
    fi
    if [ -L "/ssl/${host}.crt" ]; then
      rm -f "/ssl/${host}.crt"
    fi
  fi
done

# We can trigger dockergen rerun always because it does not call us back if list.json
# does not change, so an infinite loop does not happen.
sv hup dockergen

# We reload nginx always because content of files where links are pointing might changed.
/usr/sbin/nginx -s reload
