FROM registry.gitlab.com/tozd/docker/nginx-cron:ubuntu-focal

EXPOSE 443/tcp

VOLUME /var/log/dnsmasq
VOLUME /var/log/dockergen
VOLUME /var/log/letsencrypt
VOLUME /ssl

ENV DOCKER_HOST unix:///var/run/docker.sock
ENV LETSENCRYPT_EMAIL=
ENV LETSENCRYPT_ARGS=
ENV LOG_TO_STDOUT=0

RUN apt-get update -q -q && \
  apt-get --yes --force-yes install software-properties-common && \
  add-apt-repository --yes universe && \
  apt-get --yes --force-yes install certbot wget ca-certificates dnsmasq && \
  rm -f /etc/cron.d/certbot && \
  mkdir /dockergen && \
  wget -P /dockergen https://github.com/jwilder/docker-gen/releases/download/0.10.4/docker-gen-linux-amd64-0.10.4.tar.gz && \
  tar xf /dockergen/docker-gen-linux-amd64-0.10.4.tar.gz -C /dockergen && \
  rm -f /dockergen/docker-gen-linux-amd64-0.10.4.tar.gz && \
  mkdir -p /ssl/letsencrypt && \
  mkdir -p /letsencrypt && \
  wget -P /letsencrypt https://raw.githubusercontent.com/letsencrypt/pebble/main/test/certs/pebble.minica.pem && \
  apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* ~/.cache ~/.npm

COPY ./etc/cron.daily /etc/cron.daily
COPY ./etc/nginx /etc/nginx
COPY ./etc/service/dnsmasq /etc/service/dnsmasq
COPY ./etc/service/dockergen /etc/service/dockergen
COPY ./dockergen /dockergen
COPY ./letsencrypt /letsencrypt
