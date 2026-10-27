#!/bin/sh

set -e

DOCKER_HOST=docker

cleanup_app=0
cleanup_proxy=0
cleanup_pebble=0
cleanup_app_image=0
cleanup_pebble_image=0
cleanup_network=0
cleanup() {
  set +e

  if [ "$cleanup_app" -ne 0 ]; then
    echo "Logs app"
    docker logs test

    echo "Stopping app Docker image"
    docker stop test
    docker rm -f test
  fi

  if [ "$cleanup_proxy" -ne 0 ]; then
    echo "Logs proxy"
    docker logs proxy

    echo "Stopping proxy Docker image"
    docker stop proxy
    docker rm -f proxy
  fi

  if [ "$cleanup_pebble" -ne 0 ]; then
    echo "Logs pebble"
    docker logs pebble

    echo "Stopping Pebble Docker image"
    docker stop pebble
    docker rm -f pebble
  fi

  if [ "$cleanup_app_image" -ne 0 ]; then
    echo "Removing app Docker image"
    docker image rm -f testimage
  fi

  if [ "$cleanup_pebble_image" -ne 0 ]; then
    echo "Removing Pebble Docker image"
    docker image rm -f pebbleimage
  fi

  if [ "$cleanup_network" -ne 0 ]; then
    echo "Removing Docker network"
    docker network rm testnet
  fi
}

trap cleanup EXIT

# Waits until the proxy does not serve the site anymore.
wait_site_removed() {
  for i in $(seq 1 30); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "http://site.test$1")" = "404" ]; then
      return 0
    fi
    sleep 1
  done
  echo "Site is still served"
  return 1
}

# Waits until the proxy serves the site and checks that it is served with HTTPS from the start: when the HTTPS
# server block is enabled, HTTP requests are redirected to HTTPS, otherwise they are proxied to the app.
check_https_enabled() {
  for i in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://site.test$1")"
    case "$code" in
      301)
        return 0
        ;;
      404|000)
        ;;
      *)
        echo "Site is served without HTTPS (HTTP status $code)"
        return 1
        ;;
    esac
    sleep 1
  done
  echo "Site is not served"
  return 1
}

echo "Creating Docker network"
time docker network create testnet
cleanup_network=1

echo "Preparing"
apk add --no-cache curl

echo "Creating app Docker image"
time docker build -t testimage -f test/app.dockerfile --build-arg "IMAGE=registry.gitlab.com/tozd/docker/nginx:${TAG}" test
cleanup_app_image=1

echo "Creating Pebble Docker image"
time docker build -t pebbleimage -f test/pebble.dockerfile test
cleanup_pebble_image=1

echo "Running Pebble Docker image"
docker run -d --name pebble --network testnet -p 15000:15000 -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -e PEBBLE_AUTHZREUSE=100 pebbleimage
cleanup_pebble=1

echo "Sleeping"
sleep 5

docker cp pebble:/test/certs/pebble.minica.pem pebble.minica.pem

echo "Running proxy Docker image"
docker run -d --name proxy --network testnet --network-alias site.test -p 80:80 -p 443:443 -e LOG_TO_STDOUT=1 -e "LETSENCRYPT_EMAIL=test@example.com" -e "LETSENCRYPT_ARGS=--server https://pebble:14000/dir" -e "REQUESTS_CA_BUNDLE=/letsencrypt/pebble.minica.pem" -v "$(pwd)/pebble.minica.pem:/letsencrypt/pebble.minica.pem" -v /var/run/docker.sock:/var/run/docker.sock "${CI_REGISTRY_IMAGE}:${TAG}"
cleanup_proxy=1

echo "Running app Docker image"
docker run -d --name test --network testnet -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/ -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
ADDRESS="$(getent hosts $DOCKER_HOST | awk '{print $1}')"
echo "$ADDRESS site.test" >> /etc/hosts
wget --no-check-certificate -T 30 -q -O - https://$DOCKER_HOST:15000/roots/0 >> /etc/ssl/certs/ca-certificates.crt
wget -T 30 -q -O - https://site.test | grep -q '<title>Test site</title>'
FORWARDED_FOR="$(wget -T 30 -q -O - --header 'X-Forwarded-For: 192.0.2.1' https://site.test/forwarded-for)"
case "$FORWARDED_FOR" in
  ""|*192.0.2.1*)
    echo "Unexpected X-Forwarded-For: $FORWARDED_FOR"
    exit 1
    ;;
esac
FORWARDED_PREFIX="$(wget -T 30 -q -O - --header 'X-Forwarded-Prefix: /evil' https://site.test/forwarded-prefix)"
if [ -n "$FORWARDED_PREFIX" ]; then
  echo "Unexpected X-Forwarded-Prefix: $FORWARDED_PREFIX"
  exit 1
fi
# Older certbot versions cannot select the key type and use RSA keys.
if docker exec proxy sh -c 'certbot --help all 2>/dev/null | grep -q -- --key-type'; then
  docker exec proxy openssl x509 -noout -text -in /ssl/site.test.crt | grep -q 'Public Key Algorithm: id-ecPublicKey'
fi
if [ "$(docker exec proxy printenv NGINX_HTTPS_REJECT_UNKNOWN)" = "1" ]; then
  # curl fails with exit code 35 when the TLS handshake is rejected.
  code=0
  curl -s -k -o /dev/null --resolve "unknown.test:443:$ADDRESS" https://unknown.test || code=$?
  if [ "$code" -ne 35 ]; then
    echo "TLS handshake for an unknown host was not rejected (curl exit code $code)"
    exit 1
  fi
fi
echo "Success"

echo "Reconfiguring app Docker image"
docker stop test
sleep 1
docker rm -f test
cleanup_app=0
wait_site_removed /foo
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_URL=/foo -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Testing that recreated app has HTTPS from the start"
check_https_enabled /foo

echo "Sleeping"
sleep 20

echo "Testing"
wget -T 30 -q -O - https://site.test/foo | grep -q '<title>Test site</title>'
FORWARDED_PREFIX="$(wget -T 30 -q -O - --header 'X-Forwarded-Prefix: /evil' https://site.test/foo/forwarded-prefix)"
if [ "$FORWARDED_PREFIX" != "/foo" ]; then
  echo "Unexpected X-Forwarded-Prefix: $FORWARDED_PREFIX"
  exit 1
fi
echo "Success"

echo "Reconfiguring app Docker image"
docker stop test
sleep 1
docker rm -f test
cleanup_app=0
wait_site_removed /foo
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/foo -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Testing that recreated app has HTTPS from the start"
check_https_enabled /foo

echo "Sleeping"
sleep 20

echo "Testing"
wget -T 30 -q -O - https://site.test/foo | grep -q '<title>Foo site</title>'
echo "Success"

echo "Stopping app Docker image"
docker stop test
cleanup_app=0
for i in $(seq 1 30); do
  if ! docker exec proxy grep -q -x site.test /ssl/letsencrypt.list; then
    break
  fi
  sleep 1
done

echo "Adding manual certificates"
# A regular file, a symlink into Let's encrypt files of another host, and a listed host with manual certificates.
docker exec proxy sh -c 'printf manual > /ssl/manual.test.crt && printf manual > /ssl/manual.test.key && echo manual.test >> /ssl/letsencrypt.manual.list'
docker exec proxy sh -c 'ln -s letsencrypt/live/site.test/fullchain.pem /ssl/alias.test.crt && ln -s letsencrypt/live/site.test/privkey.pem /ssl/alias.test.key'

echo "Testing that the first daily run waits for the lock and keeps certificate links"
docker exec -d proxy flock /run/lock/letsencrypt sleep 10
sleep 1
start="$(date +%s)"
docker exec proxy /etc/cron.daily/letsencrypt
if [ "$(($(date +%s) - start))" -lt 5 ]; then
  echo "Daily run did not wait for the lock"
  exit 1
fi
docker exec proxy test -L /ssl/site.test.crt
docker exec proxy test -L /ssl/site.test.key
docker exec proxy grep -q -x site.test /ssl/letsencrypt.missing
echo "Success"

echo "Testing that the second daily run removes certificate links and keeps manual certificates"
docker exec proxy /etc/cron.daily/letsencrypt
if docker exec proxy test -L /ssl/site.test.crt || docker exec proxy test -L /ssl/site.test.key; then
  echo "Certificate links were not removed"
  exit 1
fi
test "$(docker exec proxy cat /ssl/manual.test.crt /ssl/manual.test.key)" = "manualmanual"
test "$(docker exec proxy readlink /ssl/alias.test.crt)" = "letsencrypt/live/site.test/fullchain.pem"
test "$(docker exec proxy readlink /ssl/alias.test.key)" = "letsencrypt/live/site.test/privkey.pem"
echo "Success"
