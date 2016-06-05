## `HAProxy` ACME domain validation plugin

[![Latest Version](https://img.shields.io/github/release/janeczku/haproxy-acme-validation-plugin.svg?maxAge=2592000)][release]
[![License](https://img.shields.io/github/license/janeczku/haproxy-acme-validation-plugin.svg?maxAge=2592000)]()

[release]: https://github.com/janeczku/haproxy-acme-validation-plugin/releases

HAProxy plugin implementing zero-downtime [ACME http-01](https://github.com/letsencrypt/acme-spec) validation for domains served by HAProxy instances. The plugin leverages HAProxy's Lua API to allow HAProxy to answer validation challenges using token/key-auth files provisioned by an ACME client to a designated directory.

## Compatible ACME clients

The plugin is compatible with ACME clients supporting webroot authentication for http-01 challenges.

- [Official Let's Encrypt client](https://github.com/letsencrypt/letsencrypt)
- [lego ACME client](https://github.com/xenolf/lego) (coming soon!)

## Features

### Zero-Downtime

No need to take HAProxy offline to issue or reissue certificates.
### Self-Contained

No need to leverage a backend webserver for the trivial task of serving a key authorization file once every three months per domain.

## Installation instructions

### Prerequesites

You need to be rolling HAProxy version `1.6.0` or later with Lua support enabled.
To check if your HAProxy binary was compiled with Lua support run the following command:

	haproxy -vv

If there is a line similar to this you are good to go:

	Built with Lua version

If your binary doesn't come with Lua bindings, you can download Debian/Ubuntu packages of the latest v1.6 release from the [Debian HAProxy packaging team](http://haproxy.debian.net/).

### Installation

Download the zip/tar.gz archive corresponding to your version of HAProxy from the [releases page](https://github.com/janeczku/haproxy-acme-validation-plugin/releases) and extract the files.
Copy `acme-http01-webroot.lua` to a location accessible by HAProxy. If you don't run HAProxy chrooted (`chroot` config option), you need to edit the plugin and set the `non_chroot_webroot` value to the path of the directory you want to use as your web root.

To activate the plugin you just need to add **three lines** to your `haproxy.cfg`:

In the `global` section insert

	lua-load /etc/haproxy/acme-http01-webroot.lua

to invoke the Lua plugin.

In the `frontend` section serving the domain(s) for which you want to create/renew certificates insert:

	acl url_acme_http01 path_beg /.well-known/acme-challenge/
    http-request use-service lua.acme-http01 if METH_GET url_acme_http01

This will pass ACME http-01 validation requests to the Lua plugin handler.

*Note:* ACME protocol stipulates validation on port 80. If your HTTP frontend listens on a non-standard port, make sure to add a port 80 bind directive.

Finally, soft-restart HAProxy (see below for instructions) to apply the updated configuration.

## Workflow

A complete workflow for issuing certificates using the Let's Encrypt CA for domains served by HAProxy.

An example minimal `haproxy.cfg` for this workflow is available [here](haproxy.cfg.example).

### 1. Prepare HAProxy

First, enable the `acme-http01-webroot.lua` plugin in your haproxy.cfg as described above.

Letsencrypt stores the certificate, chain and private key in `/etc/letsencrypt/live/domain.tld/`. HAProxy requires a `PEM` file that includes the certificate and corresponding private key. We need to set the `crt` directive in the `haproxy.cfg` to point to the `PEM` file which we will create later in the process.

```
...
frontend https
    bind *:443 ssl crt /etc/letsencrypt/live/www.example.com/haproxy.pem
...
```

### 2. Install `letsencrypt` client

Follow the [official guide](https://letsencrypt.readthedocs.org/en/latest/using.html#getting-the-code) to install the client.

### 3. Issue certificate

We are ready to create our certificate. Let's roll! 

We invoke the `letsencrypt` client with the [webroot method](https://letsencrypt.readthedocs.org/en/latest/using.html#webroot).
`--webroot-path` must be set to the value of the `chroot` parameter in your `haproxy.cfg`. If you are not running HAProxy chrooted you need to set it to the value of the `non_chroot_webroot` parameter configured in the Lua plugin.

	$ sudo ./letsencrypt-auto certonly --text --webroot --webroot-path \
	  /var/lib/haproxy -d www.example.com --renew-by-default --agree-tos \
	  --email your@email.com

Next, concat the certificate chain and private key to a `PEM` file suitable for HAProxy:

	$ sudo cat /etc/letsencrypt/live/www.example.com/privkey.pem \
	  /etc/letsencrypt/live/www.example.com/fullchain.pem \
	  | sudo tee /etc/letsencrypt/live/www.example.com/haproxy.pem >/dev/null

Whohaaa! Done.

### 4. Soft-restart HAProxy

We want HAProxy to reload the certificate without interrupting existing connections or introducing any sort of down-time.

Depending on your environment this can be accomplished in several ways:

#### Ubuntu/Debian command

	$ sudo service haproxy reload

#### Generic command

	$ haproxy -f /etc/haproxy/haproxy.cfg -p /var/run/haproxy.pid \
	  -sf $(cat /var/run/haproxy.pid)

or if you are up for some bash-ism:

	$ eval $(xargs -0 < /proc/$(pidof haproxy)/cmdline | \
	  awk -F '-sf' '{print $1}') -sf $(pidof haproxy)

## Certificate renewal

To renew a certificate manually just repeat steps No. 3 and 4.

### Automatic renewal

To automate renewal of certificates you can use this handy bash script: [cert-renewal-haproxy.sh](cert-renewal-haproxy.sh).

The script automates the following steps:

- Check the expiry of all the certificates under /etc/letsencrypt/live
- Renew certificates that expire in less than 4 weeks
- Create the haproxy.pem files
- Soft-restart HAProxy.

Use it in a cron job like this for weekly runs:

	$ sudo crontab -e

	5 8 * * 6 /usr/bin/cert-renewal-haproxy.sh

