# check=skip=SecretsUsedInArgOrEnv
ARG PLATFORM=linux/amd64

FROM --platform=$PLATFORM ghcr.io/jchonig/webhook

ARG PLATFORM

ENV \
        G10K_VERSION=0.10.0 \
        HOOK_SECRET= \
        HOOK_COMMAND=/usr/local/lib/push-to-g10k \
        HOOK_ARGS="-hooks /etc/webhook/githook.yaml.tmpl -template -verbose" \
        PUPPET_SERVER= \
	TZ=UTC

WORKDIR /tmp

# Install apprise and dependencies
RUN \
    echo "**** install packages ****" && \
        apk add --no-cache apprise curl git openssh-client rsync

RUN \
    echo "**** install g10k ****" && \
        G10K_OS=${PLATFORM%%/*} && \
        G10K_ARCH=${PLATFORM##*/} && \
        G10K_TARBALL="g10k_${G10K_VERSION}_${G10K_OS}_${G10K_ARCH}.tar.gz" && \
        curl -fsSLO "https://github.com/voxpupuli/g10k/releases/download/v${G10K_VERSION}/${G10K_TARBALL}" && \
        curl -fsSL "https://github.com/voxpupuli/g10k/releases/download/v${G10K_VERSION}/checksums.txt" | grep " ${G10K_TARBALL}\$" | sha256sum -c - && \
        tar -xzf "${G10K_TARBALL}" -C /usr/local/bin g10k && \
        rm "${G10K_TARBALL}"

COPY root /

EXPOSE 9000

VOLUME [ "/etc/puppetlabs/code" ]
