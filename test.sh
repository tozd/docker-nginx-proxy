#!/bin/sh

set -e

cleanup_app=0
cleanup_proxy=0
cleanup_pebble=0
cleanup_app_image=0
cleanup_pebble_image=0
cleanup_network=0
cleanup() {
  if [ "$cleanup_app" -ne 0 ]; then
    echo "Stopping app Docker image"
    docker stop test
  fi

  if [ "$cleanup_proxy" -ne 0 ]; then
    echo "Stopping proxy Docker image"
    docker stop proxy
  fi

  if [ "$cleanup_pebble" -ne 0 ]; then
    echo "Stopping Pebble Docker image"
    docker stop pebble
  fi

  if [ "$cleanup_app_image" -ne 0 ]; then
    echo "Removing app Docker image"
    docker image rm testimage
  fi

  if [ "$cleanup_pebble_image" -ne 0 ]; then
    echo "Removing Pebble Docker image"
    docker image rm pebbleimage
  fi

  if [ "$cleanup_network" -ne 0 ]; then
    echo "Removing Docker network"
    docker network rm testnet
  fi
}

trap cleanup EXIT

echo "Creating Docker network"
time docker network create testnet
cleanup_network=1

echo "Creating app Docker image"
time docker build -t testimage -f test/app.dockerfile --build-arg "IMAGE=registry.gitlab.com/tozd/docker/nginx:${TAG}" test
cleanup_app_image=1

echo "Creating Pebble Docker image"
time docker build -t pebbleimage -f test/pebble.dockerfile test
cleanup_pebble_image=1

echo "Running Pebble Docker image"
docker run -d --name pebble --network testnet --rm -p 15000:15000 -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -e PEBBLE_AUTHZREUSE=100 pebbleimage
cleanup_pebble=1

echo "Sleeping"
sleep 5

echo "Running proxy Docker image"
docker run -d --name proxy --network testnet --network-alias site.test --rm -p 80:80 -p 443:443 -e "LETSENCRYPT_EMAIL=test@example.com" -e "LETSENCRYPT_ARGS=--server https://pebble:14000/dir" -e "REQUESTS_CA_BUNDLE=/letsencrypt/pebble.minica.pem" -v /var/run/docker.sock:/var/run/docker.sock "${CI_REGISTRY_IMAGE}:${TAG}"
cleanup_proxy=1

echo "Running app Docker image"
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/ -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
ADDRESS="$(getent hosts docker | awk '{print $1}')"
echo "$ADDRESS site.test" >> /etc/hosts
wget --no-check-certificate -T 30 -q -O - https://docker:15000/roots/0 >> /etc/ssl/certs/ca-certificates.crt
wget -T 30 -q -O - https://site.test | grep -q '<title>Test site</title>'

echo "Reconfiguring app Docker image"
docker stop test
cleanup_app=0
sleep 1
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_URL=/foo -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
wget -T 30 -q -O - https://site.test/foo | grep -q '<title>Test site</title>'

echo "Reconfiguring app Docker image"
docker stop test
cleanup_app=0
sleep 1
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/foo -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
wget -T 30 -q -O - https://site.test/foo | grep -q '<title>Foo site</title>'
