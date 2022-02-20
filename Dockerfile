FROM golang:alpine AS build

ENV \
        CGO_ENABLED=0 \
	G10K_VERSION=0.8.16

WORKDIR /src/
RUN \
    echo "*** install build packages ***" && \
    apk add --no-cache curl tar git unzip && \
    echo "*** install g10k ****" && \
        cd /src && \
    git clone https://github.com/xorpaul/g10k.git && \
        cd g10k && \
        git checkout v${G10K_VERSION} && \
        BUILDTIME=$(date -u '+%Y-%m-%d_%H:%M:%S') && go build -ldflags "-s -w -X main.buildtime=$BUILDTIME" -o /usr/local/bin/g10k

FROM jchonig/webhook

ENV \
        HOOK_SECRET= \
        HOOK_COMMAND=/usr/local/lib/push-to-g10k \
        HOOK_ARGS="-hooks /etc/webhook/githook.yaml.tmpl -template -verbose" \
	TZ=UTC

WORKDIR /tmp

# Install apprise and dependencies
RUN \
    echo "**** install packages ****" && \
        apk add --no-cache cargo git libffi-dev openssh-client openssl-dev python3 python3-dev python3 py3-pip && \
    echo "*** install apprise ****" && \
      python3 -m pip install --upgrade pip setuptools && \
      python3 -m pip install --upgrade --find-links https://wheel-index.linuxserver.io/alpine/ apprise && \
      rm -rf ${HOME}/.cargo

COPY root /
COPY --from=build /usr/local/bin/g10k /usr/local/bin/g10k

EXPOSE 9000

VOLUME [ "/etc/puppetlabs/code" ]
