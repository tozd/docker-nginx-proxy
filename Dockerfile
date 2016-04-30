FROM tozd/nginx

EXPOSE 80/tcp 443/tcp

VOLUME /var/log/dnsmasq
VOLUME /var/log/dockergen
VOLUME /ssl

ENV DOCKER_HOST unix:///var/run/docker.sock

RUN apt-get update -q -q && \
 apt-get install wget ca-certificates dnsmasq --yes --force-yes && \
 mkdir /dockergen && \
 wget -P /dockergen https://github.com/jwilder/docker-gen/releases/download/0.7.0/docker-gen-linux-amd64-0.7.0.tar.gz && \
 tar xf /dockergen/docker-gen-linux-amd64-0.7.0.tar.gz -C /dockergen && \
 apt-get purge wget ca-certificates --yes --force-yes && \
 apt-get autoremove --yes --force-yes
 
COPY ./etc /etc
COPY ./dockergen /dockergen
