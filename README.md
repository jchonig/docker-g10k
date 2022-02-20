# docker-g10k
A container running [g10k](https://github.com/xorpaul/g10k) and
[webhook](https://github.com/adnanh/webhook).

The purpose is to catch webhook posts from a git server and run g10 to
build puppet environments.

This is roughly derrived from
[camptocamp/docker-g10k-webhook](https://github.com/camptocamp/docker-g10k-webhook),
but runs a container based on [s6](https://skarnet.org/software/s6/overview.html).

This image is layered on [jchonig/webhook](https://github.com/jchonig/g10k).

# Usage

## docker

```
docker create \
  --name=g10k \
  -e TZ=Europe/London \
  --expose 9000 \
  --restart unless-stopped \
  jchonig/g10k
```

### docker-compose

Compatible with docker-compose v2 schemas.

```
---
version: "3"
services:
  monit:
    image: jchonig/g10k
    container_name: g10k
    environment:
      TZ: Europe/London
      HOOK_SECRET: MYSHAREDSECRET
    volumes:
      - </path/to/appdata/config>:/config
	  - /etc/puppetlabs/code:/etc/puppetlabs/code
    expose:
      - 9000
    restart: unless-stopped
```

# Parameters

## Ports (--expose)

| Volume | Function    |
| ------ | --------    |
| 9000   | Webook port |

## Environment Variables (-e)

| Env                  | Function                                |
| ---                  | --------                                |
| PUID=1000            | for UserID - see below for explanation  |
| PGID=1000            | for GroupID - see below for explanation |
| TZ=UTC               | Specify a timezone to use EG UTC        |

## Volume Mappings (-v)

| Volume               | Function                                 |
| ------               | --------                                 |
| /config              | All the config files reside here         |
| /etc/puppetlabs/code | Where generated puppet environments live |

# Application Setup

  * Environment variables can also be passed in a file named `env` in
    the `config` directory. This file is sourced by the shell.
	
## ssh configuration

SSH configuration should be stored in the `/config/.ssh`,
    including a `/config/.ssh/config` file which specifies which keys
    to use for each git server.

```
Host git.server.adddress.com
	Compression no
	IdentityFile %d/.ssh/id_rsa
	IdentitiesOnly yes
	StrictHostKeyChecking no
	UserKnownHostsFile /dev/null
```

## Notification of hook completion

This container contains [apprise](https://github.com/caronc/apprise)
which can send notifications via almost all notification services.

To send notifications on completions of g10k runs, create a
`/config/.apprise.yml` that lists the urls to notify.

