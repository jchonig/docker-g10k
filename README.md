# docker-g10k
A container running [g10k](https://github.com/xorpaul/g10k) and
[webhook](https://github.com/adnanh/webhook).

The purpose is to catch webhook posts from a git server and run g10 to
build puppet environments.

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
version: "2"
services:
  monit:
    image: jchonig/g10k
    container_name: g10k
    environment:
      - TZ=Europe/London
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
  * PGID and PUID will be set from the ownership of
    /etc/puppetlabs/code to prevent permissions problem with the
    puppet server.

# TODO



