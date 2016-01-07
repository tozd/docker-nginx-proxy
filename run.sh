#!/bin/bash -e

# An example script to run Nginx reverse proxy in production. It uses data volumes under the $DATA_ROOT directory.
# By default /srv.

NAME='nginx'
DATA_ROOT='/srv'
NGINX_LOG="${DATA_ROOT}/${NAME}/log/nginx"
NGINX_SSL="${DATA_ROOT}/${NAME}/ssl"
NGINX_SITES="${DATA_ROOT}/${NAME}/sites"
DNSMASQ_LOG="${DATA_ROOT}/${NAME}/log/dnsmasq"
DOCKERGEN_LOG="${DATA_ROOT}/${NAME}/log/dockergen"

mkdir -p "$NGINX_LOG"
mkdir -p "$NGINX_SSL"
mkdir -p "$NGINX_SITES"
mkdir -p "$DNSMASQ_LOG"
mkdir -p "$DOCKERGEN_LOG"

docker stop "${NAME}" || true
sleep 1
docker rm "${NAME}" || true
sleep 1
docker run --detach=true --restart=always --name "${NAME}" --publish 80:80/tcp --publish 443:443/tcp \
 --volume "${NGINX_LOG}:/var/log/nginx" --volume "${NGINX_SSL}:/ssl" --volume "${NGINX_SITES}:/etc/nginx/sites-volume" \
 --volume "${DNSMASQ_LOG}:/var/log/dnsmasq" --volume "${DOCKERGEN_LOG}:/var/log/dockergen" --volume /var/run/docker.sock:/var/run/docker.sock \
 tozd/nginx-proxy
