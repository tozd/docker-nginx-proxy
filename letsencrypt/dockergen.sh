#!/bin/bash -e

# Obtains Let's encrypt certificates for listed hosts and makes them available as /ssl/<host>.key and /ssl/<host>.crt
# symlinks, existence of which the nginx template uses to enable HTTPS for a host.
#
# Without an argument (or with "event") it is run by docker-gen whenever the list of hosts changes and it only adds
# certificates and symlinks. With "cron" argument it is run daily: it also renews certificates and removes symlinks of
# hosts which have not been listed at the previous daily run either.
#
# Files and symlinks at /ssl/<host>.key and /ssl/<host>.crt which were not created by this script are manual
# certificates. They take precedence and are never modified or removed.

MODE="${1:-event}"

case "$MODE" in
  event|cron) ;;
  *)
    echo "usage: ${0##*/} [event|cron]" >&2
    exit 2
    ;;
esac

# Is Let's encrypt feature enabled?
if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
  exit 0
fi

LOCK_FILE=/run/lock/letsencrypt
LOCK_TIMEOUT_MINUTES=30
MISSING_FILE=/ssl/letsencrypt.missing

# Docker-gen and daily runs both run certbot and change symlinks, so only one run is allowed at a time. A run waits for
# the other one to finish instead of skipping, because docker-gen does not call it again for the same list of hosts.
mkdir -p "$(dirname "${LOCK_FILE}")"
exec 9>"${LOCK_FILE}"
if ! flock --wait "$((LOCK_TIMEOUT_MINUTES * 60))" 9; then
  echo "Lock '${LOCK_FILE}' was not acquired within ${LOCK_TIMEOUT_MINUTES} minutes, another run looks stuck." >&2
  exit 1
fi

mkdir -p /ssl/letsencrypt
touch /ssl/letsencrypt.list
touch /ssl/letsencrypt.manual.list

# Make sure HTTP server can access webroot even if /ssl is otherwise closed.
chmod +001 /ssl /ssl/webroot

# Returns success if the file exists and was not created by this script, i.e., it is a regular file
# or a symlink not pointing to the given target.
is_manual() {
  if [ -L "$1" ]; then
    [ "$(readlink "$1")" != "$2" ]
  else
    [ -e "$1" ]
  fi
}

FAILED=0
CHANGED=0

# List of hosts with Let's encrypt enabled.
HOSTS="$(cat /ssl/letsencrypt.list /ssl/letsencrypt.manual.list)"

for host in $HOSTS; do
  key_target="letsencrypt/live/${host}/privkey.pem"
  crt_target="letsencrypt/live/${host}/fullchain.pem"

  if is_manual "/ssl/${host}.key" "${key_target}" || is_manual "/ssl/${host}.crt" "${crt_target}"; then
    continue
  fi

  mkdir -p "/ssl/webroot/${host}"

  # Docker-gen runs call certbot only for certificates which are missing or close to expiry (e.g., when a host
  # is listed again after a long time), so that they finish quickly. Daily runs let certbot renew all certificates.
  if [ "${MODE}" = "cron" ] || ! openssl x509 -checkend "$((7 * 24 * 60 * 60))" -noout -in "/ssl/${crt_target}" >/dev/null 2>&1; then
    # certbot stores every obtained certificate into a new file and points the symlink under live/ to it.
    before="$(readlink -f "/ssl/${crt_target}" 2>/dev/null || true)"
    # Both --key-type and --cert-name are passed so that certbot renews an existing certificate with a different
    # key type immediately as ECDSA instead of refusing to renew it.
    if ! certbot --noninteractive --quiet --agree-tos --email "${LETSENCRYPT_EMAIL}" \
     --config-dir /ssl/letsencrypt certonly --webroot --keep-until-expiring --key-type ecdsa --cert-name "${host}" \
     --webroot-path "/ssl/webroot/${host}" --domain "${host}" ${LETSENCRYPT_ARGS} ; then
      echo "Obtaining or renewing certificate for '${host}' failed."
    fi
    if [ "$(readlink -f "/ssl/${crt_target}" 2>/dev/null || true)" != "${before}" ]; then
      CHANGED=1
    fi
  fi

  if [ ! -e "/ssl/${key_target}" ] || [ ! -e "/ssl/${crt_target}" ]; then
    echo "Certificate for '${host}' is missing."
    FAILED=1
    continue
  fi

  # Symlinks are created only when missing, so that they never disappear, not even briefly.
  if [ ! -L "/ssl/${host}.key" ]; then
    ln -s "${key_target}" "/ssl/${host}.key"
    CHANGED=1
  fi
  if [ ! -L "/ssl/${host}.crt" ]; then
    ln -s "${crt_target}" "/ssl/${host}.crt"
    CHANGED=1
  fi
done

# Symlinks of hosts which are not listed anymore are removed only by a daily run, and only when the host has not
# been listed at the previous daily run either. This way a container being recreated (even during a daily run)
# never loses HTTPS. The nginx template does not use symlinks of hosts without containers, so keeping them for
# a while does not matter.
if [ "${MODE}" = "cron" ]; then
  # Lists are read again because docker-gen could have changed them meanwhile.
  HOSTS="$(cat /ssl/letsencrypt.list /ssl/letsencrypt.manual.list)"

  NOT_LISTED=""
  for file in /ssl/*.key /ssl/*.crt; do
    name="${file##*/}"
    host="${name%.*}"
    if [ "${name##*.}" = "key" ]; then
      target="letsencrypt/live/${host}/privkey.pem"
    else
      target="letsencrypt/live/${host}/fullchain.pem"
    fi
    if [ ! -L "${file}" ] || [ "$(readlink "${file}")" != "${target}" ]; then
      continue
    fi
    if ! echo "${HOSTS}" | grep --quiet --line-regexp --fixed-strings "${host}"; then
      NOT_LISTED="${NOT_LISTED}${host}"$'\n'
    fi
  done

  touch "${MISSING_FILE}"
  STILL_MISSING=""
  for host in $(echo -n "${NOT_LISTED}" | sort --unique); do
    if grep --quiet --line-regexp --fixed-strings "${host}" "${MISSING_FILE}"; then
      # We make sure we are removing only symlinks created by this script.
      if [ "$(readlink "/ssl/${host}.key")" = "letsencrypt/live/${host}/privkey.pem" ]; then
        rm -f "/ssl/${host}.key"
        CHANGED=1
      fi
      if [ "$(readlink "/ssl/${host}.crt")" = "letsencrypt/live/${host}/fullchain.pem" ]; then
        rm -f "/ssl/${host}.crt"
        CHANGED=1
      fi
    else
      STILL_MISSING="${STILL_MISSING}${host}"$'\n'
    fi
  done
  echo -n "${STILL_MISSING}" > "${MISSING_FILE}.tmp"
  mv "${MISSING_FILE}.tmp" "${MISSING_FILE}"
fi

# Docker-gen and nginx are signaled only when symlinks or certificates changed, which is rarely the case for runs
# triggered by docker-gen, e.g., when a container is recreated.
if [ "${CHANGED}" = "1" ]; then
  # We trigger docker-gen rerun so that it renders the nginx template again with current symlinks. It does not
  # call this script back if the list of hosts does not change, so an infinite loop does not happen.
  pkill -HUP -P 1 docker-gen || true

  # We reload nginx as well because content of files where links are pointing might have changed.
  /usr/sbin/nginx -s reload 2>/dev/null || true
fi

exit "${FAILED}"
