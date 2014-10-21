FROM wlanslovenija/nginx

MAINTAINER Jernej Kos <jernej@kos.mx>

RUN apt-get update -q -q && \
 apt-get install wget ca-certificates --yes --force-yes && \
 mkdir /dockergen && \
 wget -P /dockergen https://github.com/jwilder/docker-gen/releases/download/0.3.4/docker-gen-linux-amd64-0.3.4.tar.gz && \
 tar xf /dockergen/docker-gen-linux-amd64-0.3.4.tar.gz -C /dockergen && \
 apt-get purge wget ca-certificates --yes --force-yes && \
 apt-get autoremove --yes --force-yes
 
COPY ./etc /etc
COPY ./dockergen /dockergen

