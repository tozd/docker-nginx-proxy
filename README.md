Image providing a reverse-proxy using [Nginx](http://nginx.org) HTTP server with support for HTTPS virtual hosts.

You can use this image as it is, or you can extend it and add configuration files for your virtual hosts.

## Automatic configuration ##

This image uses [docker-gen](https://github.com/jwilder/docker-gen) to dynamically generate Nginx configuration files
for containers exposing HTTP virtual hosts. This works automatically even across container restarts. You configure
virtual host by configuring environment variables on containers for which you want to provide a reverse proxy:
* `VIRTUAL_HOST` – a comma separated list of virtual hosts provided by the container
* `VIRTUAL_URL` – a comma separated list of URL paths provided by the container; they will be mapped to the HTTP
root (`/`) of the container
* `VIRTUAL_ALIAS` – a comma separated list of URL paths provided by the container, they will be mapped to the same
HTTP path of the container
* `VIRTUAL_PORT` – if container exposes more than one port, or you do not want to use the default port `80`, you can
configure a custom port to which a reverse proxy should connect on the container
* `VIRTUAL_NETWORK` – if container is connected to more than one network, this variable can be used to select which
network should be used (by default, the first network is used, but the order is not guaranteed)
* `VIRTUAL_LETSENCRYPT` – if set, this image will automatically generate and enable a SSL key for the virtual host
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

### HTTPS ###

If you want to use HTTPS for a virtual host, you should mount a `/ssl` volume into the container and provide
SSL key for a virtual host.

For host `example.com` you should provide `/ssl/example.com.key` and `/ssl/example.com.crt`
files. Certificate file should contain the full chain needed to validate the certificate.
If those two files exist, the image will automatically configure the virtual host to use HTTPS and redirect any
non-HTTPS traffic to HTTPS.

If you want any extra configuration for non-HTTPS traffic, you can provide `/ssl/example.com_nonssl.conf` file which
will be included for the non-HTTPS configuration. Similarly, for extra configuration for the HTTPS site, provide
`/ssl/example.com_ssl.conf` file. Of course, filenames should match the hostname of your virtual host.

### Let's encrypt ###

If you want to enable support for automatic generation of SSL keys using [Let's encrypt](https://letsencrypt.org/)
service, and you agree to [Let’s Encrypt Subscriber Agreement](https://letsencrypt.org/repository/), then you
can set `LETSENCRYPT_EMAIL` environment variable to your e-mail address when running this image to enable it. From then
on any container having `VIRTUAL_LETSENCRYPT` environment variable set will get a SSL certificate automatically
generated and enabled, and periodically renewed.

All generated keys together with Let's encrypt authentication keys are stored under `/ssl` volume.

You should probably configure [`MAILTO` environment variable](https://github.com/tozd/docker-nginx-cron) to your e-mail
address to receive reports from th daily cron job, and regularly check logs in `/var/log/letsencrypt` and
`/var/log/dockergen` volumes to see if there are any issues with key generation and renewal.
For e-mail sending to work you have to configure at least [`REMOTES` environment variable](https://github.com/tozd/docker-nginx-mailer)
as well.

## Dynamic resolving of containers ##

If extending the image, you can put sites configuration files under `/etc/nginx/sites-enabled/` to add custom sites.

Alternatively, you can mount a volume into `/etc/nginx/sites-volume/` directory and provide sites there.

To support static configuration files for containers which have dynamic IP addresses, this image configures
Nginx with an internal lightweight DNS resolver which dynamically resolves container hostnames into IPs
([when not provided by Docker](https://docs.docker.com/engine/userguide/networking/configure-dns/). Here
is an example of site configuration using DNS resolving:

```
server {
    listen 80;
    server_name example.com;
    access_log /var/log/nginx/example.com_access.log;

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
