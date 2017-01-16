FROM tozd/nginx-cron

EXPOSE 80/tcp 443/tcp

VOLUME /var/log/dnsmasq
VOLUME /var/log/dockergen
VOLUME /var/log/letsencrypt
VOLUME /ssl

ENV DOCKER_HOST unix:///var/run/docker.sock
ENV LETSENCRYPT_EMAIL=

RUN apt-get update -q -q && \
 apt-get install wget ca-certificates dnsmasq --yes --force-yes && \
 mkdir /dockergen && \
 wget -P /dockergen https://github.com/jwilder/docker-gen/releases/download/0.7.3/docker-gen-linux-amd64-0.7.3.tar.gz && \
 tar xf /dockergen/docker-gen-linux-amd64-0.7.3.tar.gz -C /dockergen && \
 mkdir /letsencrypt && \
 export XDG_DATA_HOME=/letsencrypt/data && \
 wget -P /letsencrypt https://github.com/letsencrypt/letsencrypt/archive/v0.5.0.tar.gz && \
 tar xf /letsencrypt/v0.5.0.tar.gz -C /letsencrypt --strip-components=1 && \
 rm -f /letsencrypt/v0.5.0.tar.gz && \
 cd /letsencrypt && \
 mkdir -p /ssl/letsencrypt && \
 ./letsencrypt-auto --no-self-upgrade --noninteractive --config-dir /ssl/letsencrypt --help
 
COPY ./etc /etc
COPY ./dockergen /dockergen
COPY ./letsencrypt /letsencrypt
