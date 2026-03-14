# docker-g10k
A container running [g10k](https://github.com/xorpaul/g10k) and
[webhook](https://github.com/adnanh/webhook).

The purpose is to catch webhook posts from a git server and run g10k to
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

# Development

## Running tests locally

A pre-push git hook is provided that builds the image and runs smoke tests
before allowing a push. To enable it:

```
git config core.hooksPath hooks
```

The hook will build the image, start a container, run all tests, and clean up
automatically. A failed test aborts the push.

## CI/CD

A GitHub Actions workflow (`.github/workflows/test.yml`) runs the same tests on
every push and pull request. The Docker Hub image is only built and pushed after
all tests pass, and only on pushes to `master`.

To enable the Docker Hub push, two secrets must be added to the GitHub
repository and a Docker Hub access token must be created.

### Create a Docker Hub access token

1. Log in to [hub.docker.com](https://hub.docker.com)
2. Click your avatar (top right) → **Account Settings**
3. **Security** → **New Access Token**
4. Give it a description (e.g. `github-docker-g10k`), set permissions to **Read & Write**
5. Click **Generate** and copy the token — it will not be shown again

### Add secrets to GitHub

Go to the GitHub repository → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret** and add each of the following:

| Secret               | Value                        |
| ------               | -----                        |
| `DOCKERHUB_USERNAME` | Your Docker Hub username     |
| `DOCKERHUB_TOKEN`    | The access token created above |

If you have multiple Docker Hub repositories under the same account, these
secrets can be set at the organization level instead (Settings →
Secrets and variables → Actions, on the organization page) and shared
across all repositories.

### Disable Docker Hub automated builds

Docker Hub automated builds must be **disabled** for this repository so that
the image is only published via the GitHub Action after tests pass.

1. In Docker Hub, go to the repository → **Builds**
2. Click **Configure Automated Builds**
3. Toggle automated builds **off** or unlink the GitHub source

## Notification of hook completion

This container contains [apprise](https://github.com/caronc/apprise)
which can send notifications via almost all notification services.

To send notifications on completions of g10k runs, create a
`/config/.apprise.yml` that lists the urls to notify.

