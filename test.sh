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
docker run -d --name pebble --network testnet -p 15000:15000 -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -e PEBBLE_AUTHZREUSE=100 pebbleimage
cleanup_pebble=1

echo "Sleeping"
sleep 5

echo "Running proxy Docker image"
docker run -d --name proxy --network testnet --network-alias site.test -p 80:80 -p 443:443 -e LOG_TO_STDOUT=1 -e "LETSENCRYPT_EMAIL=test@example.com" -e "LETSENCRYPT_ARGS=--server https://pebble:14000/dir" -e "REQUESTS_CA_BUNDLE=/letsencrypt/pebble.minica.pem" -v /var/run/docker.sock:/var/run/docker.sock "${CI_REGISTRY_IMAGE}:${TAG}"
cleanup_proxy=1

echo "Running app Docker image"
docker run -d --name test --network testnet -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/ -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
ADDRESS="$(getent hosts $DOCKER_HOST | awk '{print $1}')"
echo "$ADDRESS site.test" >> /etc/hosts
#wget --no-check-certificate -T 30 -q -O - https://$DOCKER_HOST:15000/roots/0 >> /etc/ssl/certs/ca-certificates.crt
wget --no-check-certificate -T 30 -q -O - https://site.test | grep -q '<title>Test site</title>'
echo "Success"

echo "Reconfiguring app Docker image"
docker stop test
sleep 1
docker rm -f test
cleanup_app=0
sleep 1
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_URL=/foo -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
wget --no-check-certificate -T 30 -q -O - https://site.test/foo | grep -q '<title>Test site</title>'
echo "Success"

echo "Reconfiguring app Docker image"
docker stop test
sleep 1
docker rm -f test
cleanup_app=0
sleep 1
docker run -d --name test --network testnet --rm -e VIRTUAL_HOST=site.test -e VIRTUAL_ALIAS=/foo -e LOG_TO_STDOUT=1 -e VIRTUAL_LETSENCRYPT=1 testimage
cleanup_app=1

echo "Sleeping"
sleep 20

echo "Testing"
wget --no-check-certificate -T 30 -q -O - https://site.test/foo | grep -q '<title>Foo site</title>'
echo "Success"
