FROM lsiobase/alpine:3.11

ARG DEBIAN_FRONTEND=noninteractive

ENV \
	G10K_VERSION=0.8.9 \
	WEBHOOK_VERSION=2.7.0 \
        HOOK_SECRET= \
	TZ=UTC

WORKDIR /home/g10k

# Set up
RUN \
    echo "**** install packages ****" && \
	apk add --no-cache curl unzip && \
    echo "*** install g10k ****" && \
	curl -L https://github.com/xorpaul/g10k/releases/download/v${G10K_VERSION}/g10k-linux-amd64.zip -o g10k-linux-amd64.zip && \
	unzip g10k-linux-amd64.zip && \
	mv g10k /usr/local/bin && \
	chmod +x /usr/local/bin/g10k && \
	rm g10k-linux-amd64.zip && \
    echo "*** install webhook ****" && \
	curl -L https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-amd64.tar.gz -o webhook-linux-amd64.tar.gz && \
	tar xzf webhook-linux-amd64.tar.gz && \
	mv webhook-linux-amd64/webhook /usr/local/bin && \
	chmod +x /usr/local/bin/webhook && \
	rm -rf webhook-linux-amd64* \
    echo "**** clean up ****" && \
	rm -rf /root/.cache /tmp/*

# Add configuration files
COPY root /

EXPOSE 9000

VOLUME [ "/etc/puppetlabs/code", "/config" ]


