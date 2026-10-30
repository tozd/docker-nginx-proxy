# tozd/nginx-proxy

<https://gitlab.com/tozd/docker/nginx-proxy>

Available as:

- [`tozd/nginx-proxy`](https://hub.docker.com/r/tozd/nginx-proxy)
- [`registry.gitlab.com/tozd/docker/nginx-proxy`](https://gitlab.com/tozd/docker/nginx-proxy/container_registry)

## Image inheritance

[`tozd/base`](https://gitlab.com/tozd/docker/base) ← [`tozd/dinit`](https://gitlab.com/tozd/docker/dinit) ← [`tozd/nginx`](https://gitlab.com/tozd/docker/nginx) ← [`tozd/nginx-mailer`](https://gitlab.com/tozd/docker/nginx-mailer) ← [`tozd/nginx-cron`](https://gitlab.com/tozd/docker/nginx-cron) ← `tozd/nginx-proxy`

## Tags

- `ubuntu-xenial`
- `ubuntu-bionic`
- `ubuntu-focal`
- `ubuntu-jammy`
- `ubuntu-noble`
- `ubuntu-resolute`

## Volumes

- `/var/log/dnsmasq`: Log files for an internal lightweight DNS resolver when one is not provided by Docker and when `LOG_TO_STDOUT` is not set to `1`.
- `/var/log/dockergen`: Log files for docker-gen when `LOG_TO_STDOUT` is not set to `1`.
- `/var/log/letsencrypt`: (Debug) log files for Let's encrypt service.
- `/ssl`: Volume with SSL keys for hosts, together with any optional extra configuration for them. All Let's encrypt generated keys together with Let's encrypt authentication keys are stored here as well. Persist this volume to not lose state.

## Variables

- `DOCKER_HOST`: Where to connect to access Docker daemon to monitor for new containers. Default is `/var/run/docker.sock` inside the container.
- `LETSENCRYPT_EMAIL`: If set, enables automatic generation of SSL keys using [Let's encrypt](https://letsencrypt.org/) service. By setting it you agree to [Let’s Encrypt Subscriber Agreement](https://letsencrypt.org/repository/).
- `LETSENCRYPT_ARGS`: Any additional arguments you might want to pass to Let's encrypt's certbot.
- `LOG_TO_STDOUT`: If set to `1` output logs to stdout (retrievable using `docker logs`) instead of log volumes.
- `NGINX_HTTPS_PORT`: If set, listen on this port for HTTPS traffic instead of the default `443`. It can also be a unix socket (e.g., `unix:/var/run/nginx.sock`), see [TLS passthrough](#tls-passthrough).
- `NGINX_HTTPS_PROTOCOLS`: Sets [SSL protocols](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_protocols) for HTTPS virtual hosts. Default is `TLSv1.2 TLSv1.3`.
- `NGINX_HTTPS_CIPHERS`: Sets [SSL ciphers](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_ciphers) for HTTPS virtual hosts. Default is `HIGH:!aNULL:!MD5`.
- `NGINX_HTTPS_REJECT_UNKNOWN`: If set to `1`, TLS handshakes for hosts without HTTPS and for clients which do not send a hostname are rejected, instead of being completed with the certificate of another host. Nginx then listens for HTTPS traffic even when no host has HTTPS. Requires nginx 1.19.4 or newer. Default is `1` on `ubuntu-noble` and `ubuntu-resolute` tags and `0` on others. Set it to `0` if you provide your own default HTTPS server.
- `DOCKERGEN_ARGS`: Additional arguments for docker-gen. Default on `ubuntu-resolute` tag is `-event-filter event=connect -event-filter event=disconnect`, so that the configuration is generated again also when containers are connected to or disconnected from networks. Not set on other tags.

## Description

Image providing a reverse-proxy using [Nginx](http://nginx.org) HTTP server with support for HTTPS virtual hosts.

You can use this image as it is, or you can extend it and add configuration files for your virtual hosts.

When `LOG_TO_STDOUT` is set to `1`, Docker image logs output to stdout and stderr. All stdout output is JSON.

## Automatic configuration

This image uses [docker-gen](https://github.com/jwilder/docker-gen) to dynamically generate Nginx configuration files
for containers exposing HTTP virtual hosts. This works automatically even across container restarts. You configure
virtual host by configuring environment variables on containers for which you want to provide a reverse proxy:

- `VIRTUAL_HOST` – a comma separated list of virtual hosts provided by the container
- `VIRTUAL_URL` – a comma separated list of URL paths provided by the container; they will be mapped to the HTTP
  root (`/`) of the container
- `VIRTUAL_ALIAS` – a comma separated list of URL paths provided by the container, they will be mapped to the same
  HTTP path of the container
- `VIRTUAL_PORT` – if container exposes more than one port, or you do not want to use the default port `80`, you can
  configure a custom port to which a reverse proxy should connect on the container
- `VIRTUAL_NETWORK` – if container is connected to more than one network, this variable can be used to select which
  network should be used (by default, the first network is used, but the order is not guaranteed)
- `VIRTUAL_LETSENCRYPT` – if set, this image will automatically generate and enable a SSL key for the virtual host
  using [Let's encrypt](https://letsencrypt.org/) service, if [Let's encrypt feature is enabled](#lets-encrypt)

When running a Docker image with your HTTP content, you can specify environment variables.

This will make the reverse proxy resolve `http://example.com/` into the `example` container:

```bash
docker run --name example ... --env VIRTUAL_HOST=example.com --env VIRTUAL_URL=/ ...
```

This will make the reverse proxy resolve `http://example.com/foo` into the `example1` container, but
This will make the reverse proxy resolve `http://example.com/bar` into the `example2` container.

```bash
docker run --name example1 ... --env VIRTUAL_HOST=example.com --env VIRTUAL_URL=/foo ...
docker run --name example2 ... --env VIRTUAL_HOST=example.com --env VIRTUAL_URL=/bar ...
```

Multiple containers can provide content for the same host and URL paths – Nginx will balance load across all of them.

A difference between `VIRTUAL_URL` and `VIRTUAL_ALIAS` is that `VIRTUAL_URL` maps all outside paths to the internal HTTP root
(`/`) of the container. This is useful when your container provides static content under the root and you want to
expose it elsewhere to the outside. But the downside is that the internal references between resources, if a container
assumes content is under `/`, might not work correctly. For example, a HTML tag `<img src="/foobar.png" />`, which
would from the perspective of the container, from the outside might resolve to something completely else, or not resolve
at all. This is why it is often better to serve content in containers under the same path as outside, and use
`VIRTUAL_ALIAS` to map them 1:1. But this means that the container has to be configured accordingly as well.

For `VIRTUAL_URL`, the reverse proxy passes the outside URL path (without a trailing `/`) to the container in the
`X-Forwarded-Prefix` HTTP request header, which some applications can use to generate correct references.

The reverse proxy passes the client's IP address to the container in `X-Real-IP` and `X-Forwarded-For` HTTP request
headers and the scheme used by the client in `X-Forwarded-Proto`. Any `X-Real-IP`, `X-Forwarded-For` and `X-Forwarded-Prefix`
headers sent by the client are replaced. If you run another reverse proxy (e.g., a CDN) in front of this one, set `SET_REAL_IP_FROM`
environment variable (inherited from [`tozd/nginx`](https://gitlab.com/tozd/docker/nginx)) to a comma separated list of its
addresses, so that the client's IP address is determined from the `X-Forwarded-For` header the proxy sends.

### HTTPS

If you want to use HTTPS for a virtual host, you should mount a `/ssl` volume into the container and provide
SSL key for a virtual host.

For host `example.com` you should provide `/ssl/example.com.key` and `/ssl/example.com.crt`
files. Certificate file should contain the full chain needed to validate the certificate.
If those two files exist, the image will automatically configure the virtual host to use HTTPS and redirect any
non-HTTPS traffic to HTTPS. When `NGINX_HTTPS_REJECT_UNKNOWN` is set to `1`, HTTPS connections for hosts without
those two files are rejected.

If you want any extra configuration for non-HTTPS traffic, you can provide `/ssl/example.com_nonssl.conf` file which
will be included for the non-HTTPS configuration. Similarly, for extra configuration for the HTTPS site, provide
`/ssl/example.com_ssl.conf` file. Of course, filenames should match the hostname of your virtual host.

### Let's encrypt

If you want to enable support for automatic generation of SSL keys using [Let's encrypt](https://letsencrypt.org/)
service, and you agree to [Let’s Encrypt Subscriber Agreement](https://letsencrypt.org/repository/), then you
can set `LETSENCRYPT_EMAIL` environment variable to your e-mail address when running this image to enable it. From then
on any container having `VIRTUAL_LETSENCRYPT` environment variable set will get a SSL certificate automatically
generated and enabled, and periodically renewed.

All generated keys together with Let's encrypt authentication keys are stored under `/ssl` volume.
For each host, `/ssl/<host>.key` and `/ssl/<host>.crt` symlinks to them are created, which enable HTTPS for the host.
A certificate is obtained as soon as a container for a new host starts and certificates are renewed daily.
Certificates use ECDSA keys. Existing certificates with other key types are replaced by the next daily run.
`ubuntu-xenial`, `ubuntu-bionic`, and `ubuntu-focal` tags use RSA keys because their certbot cannot select the key type.
If `/ssl/<host>.key` or `/ssl/<host>.crt` exist and were not created by the image (regular files or symlinks
pointing elsewhere), they take precedence and are never modified or removed.

You should probably configure [`MAILTO` environment variable](https://gitlab.com/tozd/docker/nginx-cron) to your e-mail
address to receive reports from the daily cron job, and regularly check logs in `/var/log/letsencrypt` and
`/var/log/dockergen` volumes to see if there are any issues with key generation and renewal.
For e-mail sending to work you have to configure at least [`REMOTES` environment variable](https://gitlab.com/tozd/docker/nginx-mailer)
as well.

You can list in `/ssl/letsencrypt.manual.list` file additional domains you want the container to obtain SSL keys.

### TLS passthrough

HTTPS connections can also be passed to containers without terminating TLS in this image, based on the hostname
the client sends at the start of the TLS handshake (SNI). Such a container holds its own private key and obtains its
own certificate, and traffic stays encrypted until it reaches the container. This uses Nginx's
[`ssl_preread`](https://nginx.org/en/docs/stream/ngx_stream_ssl_preread_module.html) and
[`pass`](https://nginx.org/en/docs/stream/ngx_stream_pass_module.html) in the stream module. The configuration below
requires Nginx 1.27.3 or newer. Nginx includes all files in `/etc/nginx/stream.d/` into its `stream` block.

To set it up:

1. Set `NGINX_HTTPS_PORT` to `unix:/var/run/nginx.sock`, so that HTTPS virtual hosts of this image listen on a unix
   socket and port 443 is free for the stream proxy.

2. Mount a stream configuration file into `/etc/nginx/stream.d/`, for example:

   ```nginx
   resolver 127.0.0.11 valid=5s;
   # After a failed lookup, names are looked up again after this timeout (30 seconds by default).
   resolver_timeout 5s;

   map $ssl_preread_server_name $target_backend {
       include /etc/nginx/mapstreams.d/*.conf;

       default nginx_proxy;
   }

   # Listener to which a connection is passed.
   map $target_backend $front {
       # HTTPS virtual hosts of this image.
       nginx_proxy unix:/var/run/nginx.sock;

       # Upstreams which accept the PROXY protocol, with the listener which sends it.
       include /etc/nginx/proxyprotocol.d/*.conf;

       # All other upstreams, with the listener which does not send the PROXY protocol.
       default 127.0.0.1:10002;
   }

   include /etc/nginx/upstreams.d/*.conf;

   server {
       listen 443;
       ssl_preread on;
       pass $front;
   }

   # For upstreams which accept the PROXY protocol, it sends them the client's address.
   server {
       listen 127.0.0.1:10001;
       ssl_preread on;
       proxy_pass $target_backend;
       proxy_protocol on;
   }

   # For upstreams which do not accept the PROXY protocol.
   server {
       listen 127.0.0.1:10002;
       ssl_preread on;
       proxy_pass $target_backend;
   }
   ```

   Also mount directories at `/etc/nginx/mapstreams.d/`, `/etc/nginx/upstreams.d/`, and
   `/etc/nginx/proxyprotocol.d/`, so that deployments of each container can add their own files to them.

3. For each container, add a file to `/etc/nginx/mapstreams.d/` which maps the container's hostnames to the name of
   its upstream, e.g., `/etc/nginx/mapstreams.d/app.conf`:

   ```nginx
   app.example.com app;
   ```

   And a file with the upstream to `/etc/nginx/upstreams.d/`, e.g., `/etc/nginx/upstreams.d/app.conf`:

   ```nginx
   upstream app {
       zone app 64k;
       server app:443 resolve;
   }
   ```

   Connections for `app.example.com` are then proxied to port 443 of the container with hostname `app`, which has
   to be on a network shared with this image. With `resolve`, Nginx resolves the container's address again when it
   changes. `127.0.0.11` is the DNS resolver provided by Docker, or by this image when Docker does not provide one.

4. Run the container with `VIRTUAL_HOST` (and `VIRTUAL_URL` or `VIRTUAL_ALIAS`) as usual, so that this image proxies
   non-HTTPS traffic to it (e.g., for redirects to HTTPS or for HTTP-01 challenges). Do not set `VIRTUAL_LETSENCRYPT`
   because the container obtains its certificate itself.

The server on port 443 passes the client's connection itself (instead of opening a new one) to a listener.
Connections for hostnames without a file in `/etc/nginx/mapstreams.d/` are passed to HTTPS virtual hosts of this
image, which see the client's address. Connections for containers' upstreams are passed to one of the two listeners
on the loopback interface, which proxy them to the containers.

When `NGINX_HTTPS_REJECT_UNKNOWN` is set to `1`, connections for hostnames without a passthrough entry and without
an HTTPS virtual host (and connections without a hostname) are rejected during the TLS handshake.

#### PROXY protocol

Containers receive passed through connections from the address of the container of this image, unless they accept the
[PROXY protocol](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt), with which the client's address is
sent to them. For such a container, add a file to `/etc/nginx/proxyprotocol.d/` which maps the name of its upstream
to the listener which sends the PROXY protocol header, e.g., `/etc/nginx/proxyprotocol.d/app.conf`:

```nginx
app 127.0.0.1:10001;
```

Other containers use the listener on port 10002, which does not send the PROXY protocol header.

The listener which sends the PROXY protocol header has to listen on a TCP port and not on a unix socket, because
after `pass` Nginx sends an invalid PROXY protocol header for the latter
([nginx/nginx#1912](https://github.com/nginx/nginx/issues/1912)).

If this image receives connections from IPv6 clients (`listen [::]:443;`), the listener has to have the same address
family as the client, because Nginx otherwise sends an invalid PROXY protocol header
([nginx/nginx#1609](https://github.com/nginx/nginx/issues/1609)). Add `listen [::1]:10001;` to the listener, add a
map which picks the listener based on the client's address:

```nginx
map $remote_addr $proxy_protocol_listener {
    ~:      [::1]:10001;
    default 127.0.0.1:10001;
}
```

And use it in files in `/etc/nginx/proxyprotocol.d/`, e.g., `/etc/nginx/proxyprotocol.d/app.conf`:

```nginx
app $proxy_protocol_listener;
```

## Dynamic resolving of containers

If extending the image, you can put sites configuration files under `/etc/nginx/sites-enabled/` to add custom sites.

Alternatively, you can mount a volume into `/etc/nginx/sites-volume/` directory and provide sites there.

To support static configuration files for containers which have dynamic IP addresses, this image configures
([when not provided by Docker](https://docs.docker.com/engine/userguide/networking/configure-dns/))
Nginx with an internal lightweight DNS resolver which dynamically resolves container hostnames into IPs.
Here is an example of site configuration using DNS resolving:

```
server {
    listen 80;
    server_name example.com;

    # We want to resolve container IPs dynamically, so we use a variable to make
    # Nginx resolve it again and again and not only at the start (so that it works
    # if containers change their IPs).

    location / {
        set $example example;
        proxy_pass http://$example:3000;
    }
}
```

This assumes that you have a container with hostname `example`:

```bash
docker run --name example --hostname example ...
```

By default, because of caching it can take up to 5 seconds for Nginx to start resolving a virtual host to a new
container IP address after a change.

## GitHub mirror

There is also a [read-only GitHub mirror available](https://github.com/tozd/docker-nginx-proxy),
if you need to fork the project there.
