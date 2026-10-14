# docker-g10k

A container running [g10k](https://github.com/xorpaul/g10k) and
[webhook](https://github.com/adnanh/webhook).

Image hosted at: `ghcr.io/jchonig/g10k`

The purpose is to catch webhook posts from a git server and run g10k to
build puppet environments.

This is roughly derived from
[camptocamp/docker-g10k-webhook](https://github.com/camptocamp/docker-g10k-webhook),
but runs a container based on
[s6](https://skarnet.org/software/s6/overview.html).

This image is layered on
[jchonig/webhook](https://github.com/jchonig/docker-webhook).

## Usage

### docker

```sh
docker create \
  --name=g10k \
  -e TZ=Europe/London \
  --expose 9000 \
  --restart unless-stopped \
  ghcr.io/jchonig/g10k
```

#### docker-compose

Compatible with docker-compose v2 schemas.

```yaml
---
version: "3"
services:
  monit:
    image: ghcr.io/jchonig/g10k
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

## Parameters

### Ports (--expose)

| Port | Function     |
| ---- | ------------ |
| 9000 | Webhook port |

### Environment Variables (-e)

| Env                        | Function                                   |
| -------------------------- | ------------------------------------------ |
| PUID=1000                  | for UserID - see below for explanation     |
| PGID=1000                  | for GroupID - see below for explanation    |
| TZ=UTC                     | Specify a timezone to use EG UTC           |
| PUPPET_SERVER=             | Puppet server FQDN; enables cache flushing |
| PRUNE_ENVIRONMENTS=dry-run | Prune deleted branches: yes, dry-run or no |

See [Puppet environment cache flushing](#puppet-environment-cache-flushing)
and [Pruning environments of deleted
branches](#pruning-environments-of-deleted-branches).

### Volume Mappings (-v)

| Volume                     | Function                                 |
| -------------------------- | ---------------------------------------- |
| /config                    | All the config files reside here         |
| /etc/puppetlabs/code       | Where generated puppet environments live |
| /etc/puppetlabs/puppet/ssl | Puppet SSL; needed for cache flushing    |

## Application Setup

* Environment variables can also be passed in a file named `env` in
  the `config` directory. This file is sourced by the shell.

### ssh configuration

SSH configuration should be stored in the `/config/.ssh`,
including a `/config/.ssh/config` file which specifies which keys
to use for each git server.

```ssh-config
Host git.server.adddress.com
  Compression no
  IdentityFile %d/.ssh/id_rsa
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
```

## Development

### Running tests locally

A pre-push git hook is provided that builds the image and runs smoke tests
before allowing a push. To enable it:

```sh
git config core.hooksPath hooks
```

The hook will build the image, start a container, run all tests, and clean up
automatically. A failed test aborts the push.

### CI/CD

A GitHub Actions workflow (`.github/workflows/test.yml`) runs the same tests on
every push and pull request. The Docker Hub image is only built and pushed after
all tests pass, and only on pushes to `master`.

To enable the Docker Hub push, two secrets must be added to the GitHub
repository and a Docker Hub access token must be created.

#### Create a Docker Hub access token

1. Log in to [hub.docker.com](https://hub.docker.com)
2. Click your avatar (top right) → **Account Settings**
3. **Security** → **New Access Token**
4. Give it a description (e.g. `github-docker-g10k`), set permissions to
   **Read & Write**
5. Click **Generate** and copy the token — it will not be shown again

#### Add secrets to GitHub

Go to the GitHub repository → **Settings** → **Secrets and variables** →
**Actions** → **New repository secret** and add each of the following:

| Secret               | Value                          |
| -------------------- | ------------------------------ |
| `DOCKERHUB_USERNAME` | Your Docker Hub username       |
| `DOCKERHUB_TOKEN`    | The access token created above |

If you have multiple Docker Hub repositories under the same account, these
secrets can be set at the organization level instead (Settings →
Secrets and variables → Actions, on the organization page) and shared
across all repositories.

#### Disable Docker Hub automated builds

Docker Hub automated builds must be **disabled** for this repository so that
the image is only published via the GitHub Action after tests pass.

1. In Docker Hub, go to the repository → **Builds**
2. Click **Configure Automated Builds**
3. Toggle automated builds **off** or unlink the GitHub source

### Puppet environment cache flushing

After a successful g10k deploy, the container can notify the Puppet server to
flush its compiled catalog cache for the deployed environment. This ensures
agents pick up the new code immediately rather than serving stale catalogs.

To enable this, set `PUPPET_SERVER` to the FQDN of the Puppet server and mount
its SSL directory read-only:

```yaml
environment:
  PUPPET_SERVER: puppet8.home.honig.net
volumes:
  - /etc/puppetlabs/puppet/ssl:/etc/puppetlabs/puppet/ssl:ro
```

The container uses the Puppet server's own certificate (named after
`PUPPET_SERVER`) to authenticate to the admin API. These files are
relative to `/etc/puppetlabs/puppet/ssl`:

| File                               | Purpose            |
| ---------------------------------- | ------------------ |
| `certs/ca.pem`                     | CA certificate     |
| `certs/<PUPPET_SERVER>.pem`        | Client certificate |
| `private_keys/<PUPPET_SERVER>.pem` | Private key        |

If any of these files are absent, the flush is skipped with a warning and the
deploy still succeeds. The notification title prefix is derived from the
hostname portion of `PUPPET_SERVER` (e.g. `puppet8`).

### Pruning environments of deleted branches

Deploys triggered from CI get no event when a branch is deleted, so after
each successful deploy the container lists the branches on the remote it
deployed from. It removes any environment, and any leftover staging
directory, whose branch no longer exists there. The environment just
deployed is always kept.

`PRUNE_ENVIRONMENTS` controls this:

* `dry-run` (the default) logs `Would prune environment <name>` for each
  environment that would be removed, and removes nothing
* `yes` removes them and sends one notification listing all of them
* `no` turns pruning off

Nothing is pruned if the remote's branches can't be listed, and an
environment is skipped while a deploy of it is in progress. Pruning
assumes every environment comes from the one remote being deployed, so
don't share `/etc/puppetlabs/code` between containers that deploy
different control repositories.

### Notification of hook completion

This container contains [apprise](https://github.com/caronc/apprise)
which can send notifications via almost all notification services.

To send notifications on completions of g10k runs, create a
`/config/.apprise.yml` that lists the urls to notify.
