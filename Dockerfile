# Build image with GO
FROM --platform=$BUILDPLATFORM golang:alpine AS build-go
ARG TARGETARCH
ARG TARGETOS
ARG TARGETVARIANT
WORKDIR /go

RUN apk add --no-cache git make bash build-base linux-headers

RUN git clone --depth=1 https://github.com/amnezia-vpn/amneziawg-go.git

# detect GOARM
RUN set -eux; \
    GOARM=""; \
    if [ "$TARGETARCH" = "arm" ]; then \
        GOARM="${TARGETVARIANT#v}"; \
    fi; \
    echo "GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=$GOARM"; \
    cd /go/amneziawg-go && \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=$GOARM make

# Build image with GO
FROM --platform=linux/amd64 golang:alpine AS build-linux-amd64
FROM --platform=linux/arm/v7 golang:alpine AS build-linux-armv7
FROM --platform=linux/arm64 golang:alpine AS build-linux-arm64
FROM --platform=linux/arm/v5 debian:trixie-slim AS build-linux-armv5

FROM build-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} AS build

ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS
ARG TARGETVARIANT
WORKDIR /go

RUN echo "Building for platform: $TARGETARCH" && \
    case "$TARGETPLATFORM" in \
        "linux/arm/v5") \
            apt update && apt install -y git make bash wget gcc golang ;; \
        linux/amd64 | linux/arm64 | linux/arm/v7) \
            apk add --no-cache git make bash build-base linux-headers ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM" && exit 1 ;; \
    esac

RUN git clone --depth=1 https://github.com/amnezia-vpn/amneziawg-tools.git 
RUN cd /go/amneziawg-tools/src && make

# make work structure
RUN mkdir -p /tmp/build/usr/bin/ \
    && mv /go/amneziawg-tools/src/wg /tmp/build/usr/bin/awg \
    && mv /go/amneziawg-tools/src/wg-quick/linux.bash /tmp/build/usr/bin/awg-quick
COPY wireguard-fs /tmp/build/
COPY --from=build-go /go/amneziawg-go/amneziawg-go/ /tmp/build/usr/bin/amneziawg-go
COPY entrypoint.sh /tmp/build/

# Base image for different architecture
FROM --platform=linux/amd64 alpine:latest AS linux-amd64
FROM --platform=linux/arm/v7 alpine:latest AS linux-armv7
FROM --platform=linux/arm64 alpine:latest AS linux-arm64
FROM --platform=linux/arm/v5 debian:trixie-slim AS linux-armv5

# FINAL IMAGE
FROM ${TARGETOS}-${TARGETARCH}${TARGETVARIANT}
ARG TARGETPLATFORM
ARG TARGETARCH
ARG TARGETOS
ARG TARGETVARIANT

RUN case "$TARGETPLATFORM" in \
        "linux/arm/v5") \
            apt update && \
            apt install -y bash openrc iptables openresolv iproute2 init procps iputils-ping traceroute && \
            apt autoremove -y && \
            apt clean -y && \
            rm -rf /var/cache/apt/archives /var/lib/apt/lists/* ;; \
        linux/amd64 | linux/arm64 | linux/arm/v7) \
            apk add --no-cache bash openrc iptables iptables-legacy openresolv iproute2 ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM" && exit 1 ;; \
    esac

COPY --from=build /tmp/build/ /

RUN sed -i 's/^\(tty\d\:\:\)/#\1/' /etc/inittab && \
  sed -i \
  -e 's/^#\?rc_env_allow=.*/rc_env_allow="\*"/' \
  -e 's/^#\?rc_sys=.*/rc_sys="docker"/' \
  /etc/rc.conf && \
  ### alpine
  if [ -f /usr/libexec/rc/sh/init.sh ]; then \
      sed -i -e 's/VSERVER/DOCKER/' -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' /usr/libexec/rc/sh/init.sh; \
  fi && \
  ### debian
  if [ -f /lib/rc/sh/init.sh ]; then \
      sed -i -e 's/VSERVER/DOCKER/' -e 's/checkpath -d "$RC_SVCDIR"/mkdir "$RC_SVCDIR"/' /lib/rc/sh/init.sh; \
      sed -i '/^depend()/,/^}/d' /etc/init.d/wg-quick; \
  fi && \
  ###
  rm -f \
  /etc/init.d/hwdrivers \
  /etc/init.d/machine-id && \
  # IPv4
  rm /usr/sbin/iptables /usr/sbin/iptables-save /usr/sbin/iptables-restore && \
  ln -s /usr/sbin/iptables-legacy /usr/sbin/iptables && \
  ln -s /usr/sbin/iptables-legacy-save /usr/sbin/iptables-save && \
  ln -s /usr/sbin/iptables-legacy-restore /usr/sbin/iptables-restore && \
  # IPv6
  rm /usr/sbin/ip6tables /usr/sbin/ip6tables-save /usr/sbin/ip6tables-restore && \
  ln -s /usr/sbin/ip6tables-legacy /usr/sbin/ip6tables && \
  ln -s /usr/sbin/ip6tables-legacy-save /usr/sbin/ip6tables-save && \
  ln -s /usr/sbin/ip6tables-legacy-restore /usr/sbin/ip6tables-restore && \
  #
  mkdir -p /etc/amnezia/amneziawg/ && \
  #
  chmod +x /etc/init.d/wg-quick && \
  chmod +x /data/pre_up.sh && \
  #
  rc-update add wg-quick default && \
  chmod +x /entrypoint.sh

VOLUME ["/sys/fs/cgroup"]
ENTRYPOINT ["/entrypoint.sh"]