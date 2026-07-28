FROM golang:alpine AS build

ARG xray_tag=v26.2.6
ARG TARGETARCH=amd64

RUN case "${TARGETARCH}" in \
        amd64) PLATFORM="linux-amd64" ;; \
        arm64) PLATFORM="linux-arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac && \
    echo "${PLATFORM}" > /tmp/platform

RUN apk add --update git build-base libmnl-dev nftables
WORKDIR /src

# Build xray-core
RUN git clone --depth 1 -b $xray_tag https://github.com/XTLS/Xray-core.git /src
RUN CGO_ENABLED=0 go build -o xray -trimpath -buildvcs=false -gcflags="all=-l=4" -ldflags "-s -w -buildid=" ./main

# Download geodat into a staging directory
ADD https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geoip.dat /tmp/geodat/geoip.dat
ADD https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/geosite.dat /tmp/geodat/geosite.dat

RUN mkdir -p /tmp/empty

# Create config files with empty JSON content
RUN mkdir -p /tmp/usr/local/etc/xray
RUN cat <<EOF >/tmp/usr/local/etc/xray/00_log.json
{
  "log": {
    "error": "/var/log/xray/error.log",
    "loglevel": "warning",
    "access": "none",
    "dnsLog": false
  }
}
EOF
RUN echo '{}' >/tmp/usr/local/etc/xray/01_api.json
RUN echo '{}' >/tmp/usr/local/etc/xray/02_dns.json
RUN echo '{}' >/tmp/usr/local/etc/xray/03_routing.json
RUN echo '{}' >/tmp/usr/local/etc/xray/04_policy.json
RUN echo '{}' >/tmp/usr/local/etc/xray/05_inbounds.json
RUN echo '{}' >/tmp/usr/local/etc/xray/06_outbounds.json
RUN echo '{}' >/tmp/usr/local/etc/xray/07_transport.json
RUN echo '{}' >/tmp/usr/local/etc/xray/08_stats.json
RUN echo '{}' >/tmp/usr/local/etc/xray/09_reverse.json

# Create log files
RUN mkdir -p /tmp/var/log/xray && touch \
  /tmp/var/log/xray/access.log \
  /tmp/var/log/xray/error.log

# Build finally image
FROM alpine:latest

COPY --from=build --chown=0:0 --chmod=755 /src/xray /usr/local/bin/xray
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /usr/local/share/xray
COPY --from=build --chown=0:0 --chmod=644 /tmp/geodat/*.dat /usr/local/share/xray/
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /usr/local/etc/xray
COPY --from=build --chown=0:0 --chmod=644 /tmp/usr/local/etc/xray/*.json /usr/local/etc/xray/
COPY --from=build --chown=0:0 --chmod=755 /tmp/empty /var/log/xray
COPY --from=build --chown=65532:65532 --chmod=600 /tmp/var/log/xray/*.log /var/log/xray/

VOLUME /usr/local/etc/xray
VOLUME /var/log/xray

RUN apk add --no-cache --update bash libmnl nftables openresolv iproute2

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY ip_setup.sh /ip_setup.sh
RUN chmod +x /ip_setup.sh

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/usr/local/bin/xray", "-confdir", "/usr/local/etc/xray/" ]