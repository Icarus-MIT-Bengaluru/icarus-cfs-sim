#!/bin/sh
# cFS must start in its staged cpu1 directory so it can find its startup script
# and dynamically loaded modules.
#
# The /logs bind mount is treated as OPTIONAL. If it is missing or unwritable
# the OBC still runs and still emits everything on stdout, where `docker logs`
# captures it -- mirroring what controllers/udp-echo-server.c does. Phase 6
# injects an unavailable log mount as a fault, so dying here would turn an
# observable degradation into an outage.
#
# Per-app logs are produced HERE, at the boundary, rather than by the apps: each
# ICARUS app emits only EVS events (idiomatic cFS), and the splitter below
# routes them into one file per app. See docs/peripherals.md and docs/testing.md.
set -eu

log_dir=/logs
log_file="$log_dir/cfe-console.log"
log_ok=0

# Probe with touch, not `: >>file`: a REDIRECTION failure is reported by the
# shell itself and is not suppressed by the command's own 2>/dev/null, so the
# redirect form printed an error and exited before the test could be evaluated.
# touch is a command, so its stderr and exit status behave as expected.
if mkdir -p "$log_dir" 2>/dev/null && touch "$log_file" 2>/dev/null; then
    log_ok=1
else
    printf 'WARNING: %s is unavailable or unwritable; console output goes to stdout only.\n' \
        "$log_dir" >&2
fi

note() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
    [ "$log_ok" = "1" ] && printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"$log_file"
    return 0
}

note 'OBC container starting cFS native_std'

cd /opt/icarus/cfs/exe/cpu1

# Test affordance, not flight behaviour: ICARUS_DISABLED_APPS names apps to drop
# from the startup script before cFE boots, so isolation can be proved without
# rebuilding the image.  Edits the container's own copy; the image is untouched.
startup_scr=/opt/icarus/cfs/exe/cpu1/cf/cfe_es_startup.scr
if [ -n "${ICARUS_DISABLED_APPS:-}" ]; then
    for disabled_app in $ICARUS_DISABLED_APPS; do
        sed -i "/CFE_APP, *${disabled_app}[, ]/d" "$startup_scr"
        note "OBC startup: app $disabled_app DISABLED for this run"
    done
fi

# awk splits the console stream by originating app while passing everything
# through.  Matching on the EVS "/<APP_NAME> " field keeps an app's own events
# in its own file; a line merely mentioning another app does not leak.
# With no usable log dir the splitter is skipped and output goes straight out.
if [ "$log_ok" = "1" ]; then
    stdbuf -oL -eL ./core-cpu1 2>&1 \
        | stdbuf -oL awk -v logdir="$log_dir" '
            {
                print
                fflush()
                app = ""
                if (match($0, /\/ADCS_SIM +[0-9]+:/))         { app = "adcs_sim" }
                else if (match($0, /\/PAYLOAD_SIM +[0-9]+:/)) { app = "payload_sim" }
                else if (match($0, /\/COMMS_SIM +[0-9]+:/))   { app = "comms_sim" }
                if (app != "") {
                    f = logdir "/" app ".log"
                    print >> f
                    fflush(f)
                }
            }' \
        | tee -a "$log_file" &
else
    stdbuf -oL -eL ./core-cpu1 2>&1 &
fi
pipeline_pid=$!

terminate() {
    note 'OBC container stopping cFS native_std'
    kill -TERM "$pipeline_pid" 2>/dev/null || true
    wait "$pipeline_pid" 2>/dev/null || true
    exit 0
}

trap terminate INT TERM
wait "$pipeline_pid"
