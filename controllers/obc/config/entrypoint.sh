#!/bin/sh
# cFS must start in its staged cpu1 directory so it can find its startup script
# and dynamically loaded modules.  Console output is retained on the host via
# the /logs bind mount supplied by run.sh.
set -eu

log_file="/logs/cfe-console.log"
mkdir -p /logs
printf '%s OBC container starting cFS native_std\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$log_file"

cd /opt/icarus/cfs/exe/cpu1
stdbuf -oL -eL ./core-cpu1 2>&1 | tee -a "$log_file" &
pipeline_pid=$!

terminate() {
    kill -TERM "$pipeline_pid" 2>/dev/null || true
    wait "$pipeline_pid" 2>/dev/null || true
    exit 0
}

trap terminate INT TERM
wait "$pipeline_pid"
