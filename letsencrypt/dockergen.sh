#!/bin/bash -e

# Is Let's encrypt feature enabled?
if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  exit 0
fi

mkdir -p /ssl/letsencrypt

# We have to remove the last comma to make it a valid JSON.
LIST_JSON="$(cat /ssl/webroot/list.json | sed -n 'x;${s/,$//;p;x}; 2,$ p')"
# List of hosts in the JSON file.
HOSTS="$(echo "${LIST_JSON}" | jq --raw-output 'keys | .[]')"

for host in $HOSTS; do
  mkdir -p "/ssl/webroot/${host}"
done

# TODO: Remove "--test-cert" which is currently using for testing.
/letsencrypt/letsencrypt-auto --no-self-upgrade --noninteractive --agree-tos --email "${LETSENCRYPT_EMAIL}" \
 --config-dir /ssl/letsencrypt certonly --webroot --test-cert --keep-until-expiring --rsa-key-size 4096 \
 --webroot-map "${LIST_JSON}"

# Has existence of any link changed?
CHANGED=""

for host in $HOSTS; do
  if [ ! -e "letsencrypt/live/${host}/privkey.pem" ]; then
    echo "File 'letsencrypt/live/${host}/privkey.pem' is missing."
    exit 1
  fi
  if [ ! -e "letsencrypt/live/${host}/fullchain.pem" ]; then
    echo "File 'letsencrypt/live/${host}/fullchain.pem' is missing."
    exit 1
  fi

  # This does not check if the symlink itself exists, but if the file to which is pointing exists.
  # This is the same check as it is done in the nginx template so it works as expected:
  # we want to rerun dockergen only when existence of any file used by the nginx template changes.
  if [ ! -e "/ssl/${host}.key" ] || [ ! -e "/ssl/${host}.crt" ]; then
    CHANGED="true"
  fi

  # We use -f just to be sure.
  ln -f -s "letsencrypt/live/${host}/privkey.pem" "/ssl/${host}.key"
  ln -f -s "letsencrypt/live/${host}/fullchain.pem" "/ssl/${host}.crt"
done

EXISTING_HOSTS="$(find /ssl -maxdepth 1 -lname 'letsencrypt*' -printf '%f\n' | rev | cut --fields=2- --delimiter '.' | rev | sort --unique)"

for host in $EXISTING_HOSTS; do
  if ! echo "${HOST}" | grep --quiet --line-regexp --fixed-strings "$host"; then
    # We set CHANGED even if we might be deleting only a stale symlink which is not pointing
    # towards any file anymore (and which previous run of dockergen already ignored as nonexistent)
    # because it might be that the file to which a symlink is pointing was deleted between previous
    # run to dockergen and now, without it running again. We might run dockergen once now without
    # a real reason, but we at least are not out of sync and still will not get into a loop.
    CHANGED="true"

    # We use -f just to be sure.
    rm -f "/ssl/${host}.key" "/ssl/${host}.crt"
  fi
done

# If existence of any link changed, dockergen has to rerun because nginx
# template depends on existence of key files. We call it only when
# there are changes because otherwise we could create an infinite loop
# (dockergen calls this script again).
if [[ -n "${CHANGED}" ]]; then
  sv hup dockergen
fi

# We reload nginx always because content of files where links are pointing might changed.
/usr/sbin/nginx -s reload
