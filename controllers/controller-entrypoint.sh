#!/bin/sh
# ICARUS controller container entrypoint.
#
# Phase 3: hands off to the UDP echo server, which binds the configured port and
# logs every receive, send, and rejection.  The server owns the process from
# here so signals reach it directly.
set -eu

: "${CONTROLLER_NAME:?CONTROLLER_NAME must be set}"
: "${CONTROLLER_UDP_PORT:?CONTROLLER_UDP_PORT must be set}"

mkdir -p /logs

exec /usr/local/bin/icarus-udp-echo-server
