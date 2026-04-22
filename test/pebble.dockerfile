FROM ghcr.io/letsencrypt/pebble:2.10.1

COPY ./pebble-config.json /test/config/pebble-config.json
