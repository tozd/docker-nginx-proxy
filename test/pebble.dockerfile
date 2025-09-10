FROM ghcr.io/letsencrypt/pebble:2.8.0

COPY ./pebble-config.json /test/config/pebble-config.json
