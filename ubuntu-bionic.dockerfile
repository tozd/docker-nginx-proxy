FROM tozd/nginx-cron:ubuntu-bionic

EXPOSE 80/tcp 443/tcp

VOLUME /var/log/dnsmasq
VOLUME /var/log/dockergen
VOLUME /var/log/letsencrypt
VOLUME /ssl

ENV DOCKER_HOST unix:///var/run/docker.sock
ENV LETSENCRYPT_EMAIL=

RUN apt-get update -q -q && \
 apt-get --yes --force-yes install software-properties-common && \
 add-apt-repository --yes universe && \
 add-apt-repository --yes ppa:certbot/certbot && \
 apt-get  --yes --force-yes install certbot wget ca-certificates dnsmasq && \
 rm -f /etc/cron.d/certbot && \
 mkdir /dockergen && \
 wget -P /dockergen https://github.com/jwilder/docker-gen/releases/download/0.7.4/docker-gen-linux-amd64-0.7.4.tar.gz && \
 tar xf /dockergen/docker-gen-linux-amd64-0.7.4.tar.gz -C /dockergen && \
 rm -f /dockergen/docker-gen-linux-amd64-0.7.4.tar.gz && \
 mkdir -p /ssl/letsencrypt && \
 apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* ~/.cache ~/.npm

COPY ./etc /etc
COPY ./dockergen /dockergen
COPY ./letsencrypt-bionic /letsencrypt
