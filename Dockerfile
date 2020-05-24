FROM lsiobase/ubuntu:focal

ARG DEBIAN_FRONTEND=noninteractive

ENV \
	G10K_VERSION=0.8.9 \
	WEBHOOK_VERSION=2.7.0 \
        HOOK_SECRET= \
	TZ=UTC

WORKDIR /tmp

# Set up
RUN \
    echo "**** install packages ****" && \
	apt update && \
	apt -y install git unzip && \
    echo "*** install g10k ****" && \
	curl -L https://github.com/xorpaul/g10k/releases/download/v${G10K_VERSION}/g10k-linux-amd64.zip -o g10k-linux-amd64.zip && \
	unzip g10k-linux-amd64.zip && \
	install -m 755 g10k /usr/local/bin && \
	rm g10k-linux-amd64.zip && \
    echo "*** install webhook ****" && \
	curl -L https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz | tar xzf - && \
	install -m 755 webhook-linux-amd64/webhook /usr/local/bin && \
	rm -rf webhook-linux-amd64* \
    echo "**** clean up ****" && \
	apt purge -y unzip && \
	apt clean && \
        apt autoremove && \
	rm -rf /var/lib/apt/lists/*

COPY root /
COPY g10k.yaml.tmpl /etc/webhook/g10k.yaml.tmpl
COPY push-to-g10k /usr/local/lib/push-to-g10k

EXPOSE 9000

VOLUME [ "/etc/puppetlabs/code", "/config" ]


