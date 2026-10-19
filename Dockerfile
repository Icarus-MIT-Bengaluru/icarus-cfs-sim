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
COPY controllers/obc/tools/cfe-cmd.c ./

# The echo server runs on BusyBox, which has no libc, so it must be static.
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror -static \
        -o /out-udp-echo-server udp-echo-server.c

# The probe runs on Debian and needs glibc's resolver for container aliases, so
# it is dynamically linked on purpose.
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror \
        -o /out-udp-probe udp-probe.c

# Ground-command sender for Phase 6 fault injection and Phase 7 recovery.
RUN gcc -std=c11 -O2 -Wall -Wextra -Werror \
        -o /out-cfe-cmd cfe-cmd.c

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

# Project-owned app sources, kept OUTSIDE the vendor tree. CFS_APP_PATH accepts
# absolute paths, so cFS finds them without anything being written into cfs/.
COPY apps/ /opt/icarus/apps/

# Project-owned mission overlay. sample_defs is copied to icarus_defs and the
# ICARUS files are layered on top, so the overlay carries only what it changes
# and the submodule itself is never modified.
RUN cp -r sample_defs icarus_defs
COPY controllers/obc/config/mission/ /opt/icarus/cfs/icarus_defs/

# native_std is cFS's supported native Linux development configuration.
# PREP_OPTS_native_std is assigned on the command line, which overrides the
# in-makefile `+=` and propagates to the sub-make; MISSIONCONFIG=icarus then
# resolves MISSION_DEFS to icarus_defs.
ENV CFS_APP_PATH=/opt/icarus/apps
RUN make native_std.prep \
        PREP_OPTS_native_std="-DENABLE_UNIT_TESTS=TRUE -DSIMULATION=native -DCFE_EDS_ENABLED=OFF -DMISSIONCONFIG=icarus -DCMAKE_BUILD_TYPE=debug" \
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
COPY controllers/obc/tools/rate-check.sh /usr/local/bin/icarus-rate-check
COPY --from=tools /out-udp-probe /usr/local/bin/icarus-udp-probe
COPY --from=tools /out-cfe-cmd /usr/local/bin/icarus-cfe-cmd

RUN chmod 0755 /usr/local/bin/icarus-obc-entrypoint \
                /usr/local/bin/icarus-rate-check \
                /usr/local/bin/icarus-udp-probe \
                /usr/local/bin/icarus-cfe-cmd

WORKDIR /opt/icarus/cfs/exe/cpu1
ENTRYPOINT ["/usr/local/bin/icarus-obc-entrypoint"]
