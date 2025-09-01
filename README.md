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
- `NGINX_HTTPS_PORT`: If set, listen on this port for HTTPS traffic instead of the default `443`.
- `NGINX_HTTPS_PROTOCOLS`: Sets [SSL protocols](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_protocols) for HTTPS virtual hosts. Default is `TLSv1.2 TLSv1.3`.
- `NGINX_HTTPS_CIPHERS`: Sets [SSL ciphers](https://nginx.org/en/docs/http/ngx_http_ssl_module.html#ssl_ciphers) for HTTPS virtual hosts. Default is `HIGH:!aNULL:!MD5`.

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

### HTTPS

If you want to use HTTPS for a virtual host, you should mount a `/ssl` volume into the container and provide
SSL key for a virtual host.

For host `example.com` you should provide `/ssl/example.com.key` and `/ssl/example.com.crt`
files. Certificate file should contain the full chain needed to validate the certificate.
If those two files exist, the image will automatically configure the virtual host to use HTTPS and redirect any
non-HTTPS traffic to HTTPS.

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

You should probably configure [`MAILTO` environment variable](https://gitlab.com/tozd/docker/nginx-cron) to your e-mail
address to receive reports from th daily cron job, and regularly check logs in `/var/log/letsencrypt` and
`/var/log/dockergen` volumes to see if there are any issues with key generation and renewal.
For e-mail sending to work you have to configure at least [`REMOTES` environment variable](https://gitlab.com/tozd/docker/nginx-mailer)
as well.

You can list in `/ssl/letsencrypt.manual.list` file additional domains you want the container to obtain SSL keys.

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
