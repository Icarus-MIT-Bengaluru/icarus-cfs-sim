# syntax=docker/dockerfile:1
#
# ICARUS images.  Three roles, built from one file:
#   tools      - compiles the small project-owned C utilities
#   controller - BusyBox device simulator (no cFS dependency)
#   obc        - Debian runtime carrying the compiled cFS core

# Project-owned C utilities.  Kept minimal and independent of the cFS build so
# `--target controller` stays fast.
FROM debian:bookworm-slim AS tools

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY controllers/udp-echo-server.c ./
COPY controllers/obc/tools/udp-probe.c ./

# The echo server runs on BusyBox, which has no libc, so it must be static.
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror -static \
        -o /out-udp-echo-server udp-echo-server.c

# The probe runs on Debian and needs glibc's resolver for container aliases, so
# it is dynamically linked on purpose.
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror \
        -o /out-udp-probe udp-probe.c

# Phase 2+ controller image.  No dependency on the cFS build stage.
FROM busybox:1.36.1-musl AS controller

LABEL org.opencontainers.image.title="ICARUS controller simulator" \
      org.opencontainers.image.description="UDP device simulator for ADCS, Payload, and Comms"

COPY controllers/controller-entrypoint.sh /usr/local/bin/icarus-controller-entrypoint
COPY --from=tools /out-udp-echo-server /usr/local/bin/icarus-udp-echo-server
RUN chmod 0755 /usr/local/bin/icarus-controller-entrypoint \
                /usr/local/bin/icarus-udp-echo-server \
    && mkdir -p /logs

ENTRYPOINT ["/usr/local/bin/icarus-controller-entrypoint"]

# cFS build stage.  cFS is built from the pinned cfs/ submodule rather than
# downloaded during the image build, so the produced binary is repeatable.
FROM debian:bookworm-slim AS builder

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        cmake \
        git \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/icarus/cfs
COPY cfs/ ./

# native_std is cFS's supported native Linux development configuration.
RUN make native_std.prep \
    && make native_std.install

FROM debian:bookworm-slim AS obc

ARG DEBIAN_FRONTEND=noninteractive
ARG CFS_VERSION=v7.0.1
LABEL org.opencontainers.image.title="ICARUS cFS OBC" \
      org.opencontainers.image.description="Single-node cFS OBC" \
      org.opencontainers.image.version="${CFS_VERSION}"

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        coreutils \
        libc6 \
        libgcc-s1 \
        libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir --parents /logs

COPY --from=builder /opt/icarus/cfs/build-native_std/exe/cpu1/ /opt/icarus/cfs/exe/cpu1/
COPY controllers/obc/config/entrypoint.sh /usr/local/bin/icarus-obc-entrypoint
COPY --from=tools /out-udp-probe /usr/local/bin/icarus-udp-probe

RUN chmod 0755 /usr/local/bin/icarus-obc-entrypoint \
                /usr/local/bin/icarus-udp-probe

WORKDIR /opt/icarus/cfs/exe/cpu1
ENTRYPOINT ["/usr/local/bin/icarus-obc-entrypoint"]
