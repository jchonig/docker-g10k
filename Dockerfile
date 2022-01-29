FROM golang:alpine AS build

ENV \
        CGO_ENABLED=0 \
	G10K_VERSION=0.8.16 \
	WEBHOOK_VERSION=2.8.0

WORKDIR /src/
RUN \
    echo "*** install build packages ***" && \
    apk add --no-cache curl tar git unzip && \
    echo "*** Build webhook ***" && \
        cd /src && \
        git clone https://github.com/adnanh/webhook.git && \
        cd webhook && \
        git checkout ${WEBHOOK_VERSION} && \
        go build -o /usr/local/bin/webhook && \
    echo "*** install g10k ****" && \
        cd /src && \
    git clone https://github.com/xorpaul/g10k.git && \
        cd g10k && \
        git checkout v${G10K_VERSION} && \
        BUILDTIME=$(date -u '+%Y-%m-%d_%H:%M:%S') && go build -ldflags "-s -w -X main.buildtime=$BUILDTIME" -o /usr/local/bin/g10k

FROM lsiobase/alpine:3.15

ENV \
        HOOK_SECRET= \
	TZ=UTC

WORKDIR /tmp

# Set up
RUN \
    echo "**** install packages ****" && \
        apk add --no-cache cargo git libffi-dev openssh-client openssl-dev python3 python3-dev python3 py3-pip && \
    echo "*** install apprise ****" && \
      python3 -m pip install --upgrade pip setuptools && \
      python3 -m pip install --upgrade --find-links https://wheel-index.linuxserver.io/alpine/ apprise && \
      rm -rf ${HOME}/.cargo

COPY root /
COPY g10k.yaml.tmpl /etc/webhook/g10k.yaml.tmpl
COPY push-to-g10k /usr/local/lib/push-to-g10k
COPY --from=build /usr/local/bin/webhook /usr/local/bin/webhook
COPY --from=build /usr/local/bin/g10k /usr/local/bin/g10k

EXPOSE 9000

VOLUME [ "/etc/puppetlabs/code", "/config" ]


