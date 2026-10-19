#!/usr/bin/env bash
# Lifecycle and phase-gate interface for the ICARUS containers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBC_DIR="$ROOT_DIR/controllers/obc"
OBC_CONFIG_DIR="$OBC_DIR/config"
OBC_LOG_DIR="$OBC_DIR/logs"
UDP_CONFIG_FILE="$OBC_CONFIG_DIR/udp.env"
# Images are tagged by role, not by phase: the same image serves every phase
# that has been reached, so a phase-numbered tag goes stale on each advance.
CONTROLLER_IMAGE_TAG="icarus-controller:dev"
# Grace period for SIGTERM before Docker escalates to SIGKILL.
CONTAINER_STOP_TIMEOUT_SECONDS=5
CONTROLLERS=(adcs payload comms)

# shellcheck source=controllers/obc/config/runtime.env
set -a
source "$OBC_CONFIG_DIR/runtime.env"
set +a

usage() {
    cat <<'EOF'
Usage: ./run.sh <command>

Commands:
  build              Build the pinned cFS OBC image.
  build-controllers  Build the lightweight controller simulator image.
  start-obc          Start only the OBC on the private ICARUS network.
  start              Start the OBC and all controller containers.
  stop               Stop/remove all ICARUS containers and the private network.
  status             Show every ICARUS container state.
  logs [name]        Stream logs for obc (default), adcs, payload, or comms.
  clean-logs         Remove generated logs while retaining .gitkeep files.
  phase 1            Build, start, and verify the Phase 1 OBC gate.
  phase 2            Build, start, and verify the Phase 2 container-mesh gate.
  phase 3            Build, start, and verify the Phase 3 UDP transport gate.
  phase 4            Build, start, and verify the Phase 4 app-integration gate.
  phase 5            Build, start, and verify the Phase 5 scheduler-rate gate.
  phase 6            Build, start, and verify the Phase 6 fault-containment gate.
  phase 7            Build, start, and verify the Phase 7 recovery-ladder gate.
EOF
}

require_docker() {
    command -v docker >/dev/null 2>&1 || {
        echo "Docker is required but was not found on PATH." >&2
        exit 1
    }
    docker info >/dev/null 2>&1 || {
        echo "Docker is installed but its daemon is not available." >&2
        exit 1
    }
}

ensure_log_dirs() {
    local controller
    mkdir -p "$OBC_LOG_DIR"
    for controller in "${CONTROLLERS[@]}"; do
        mkdir -p "$ROOT_DIR/controllers/$controller/logs"
    done
}

load_controller_config() {
    local controller="$1"
    # shellcheck source=/dev/null
    set -a
    source "$ROOT_DIR/controllers/$controller/config/runtime.env"
    set +a
}

container_exists() {
    local container_name="$1"
    docker container inspect "$container_name" >/dev/null 2>&1
}

container_running() {
    local container_name="$1"
    [ "$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)" = "true" ]
}

ensure_network() {
    if ! docker network inspect "$ICARUS_NETWORK_NAME" >/dev/null 2>&1; then
        docker network create --driver bridge --internal "$ICARUS_NETWORK_NAME" >/dev/null
        echo "Created private Docker network '$ICARUS_NETWORK_NAME'."
    fi
}

container_on_icarus_network() {
    local container_name="$1"
    docker inspect --format '{{range $name, $network := .NetworkSettings.Networks}}{{printf "%s " $name}}{{end}}' \
        "$container_name" | grep -Fqx "$ICARUS_NETWORK_NAME "
}

build() {
    require_docker
    docker build --target obc --tag "$OBC_IMAGE" --build-arg "CFS_VERSION=$CFS_VERSION" "$ROOT_DIR"
}

build_controllers() {
    require_docker
    docker build --target controller --tag "$CONTROLLER_IMAGE_TAG" "$ROOT_DIR"
}

start_obc() {
    require_docker
    ensure_log_dirs
    ensure_network

    if container_exists "$OBC_CONTAINER_NAME"; then
        if container_running "$OBC_CONTAINER_NAME"; then
            echo "OBC container '$OBC_CONTAINER_NAME' is already running."
            return
        fi
        docker start "$OBC_CONTAINER_NAME" >/dev/null
    else
        docker run --detach \
            --name "$OBC_CONTAINER_NAME" \
            --sysctl fs.mqueue.msg_max=64 \
            --network "$ICARUS_NETWORK_NAME" \
            --network-alias obc \
            --env "ICARUS_DISABLED_APPS=${ICARUS_DISABLED_APPS:-}" \
            --mount "type=bind,source=$OBC_LOG_DIR,target=/logs" \
            "$OBC_IMAGE" >/dev/null
    fi

    echo "Started OBC container '$OBC_CONTAINER_NAME'."
}

start_controller() {
    local controller="$1"
    local controller_dir="$ROOT_DIR/controllers/$controller"
    load_controller_config "$controller"
    mkdir -p "$controller_dir/logs"

    if container_exists "$CONTROLLER_CONTAINER_NAME"; then
        if container_running "$CONTROLLER_CONTAINER_NAME"; then
            echo "Controller '$controller' is already running."
            return
        fi
        docker start "$CONTROLLER_CONTAINER_NAME" >/dev/null
    else
        docker run --detach \
            --name "$CONTROLLER_CONTAINER_NAME" \
            --label "icarus.role=controller" \
            --label "icarus.controller=$CONTROLLER_NAME" \
            --network "$ICARUS_NETWORK_NAME" \
            --network-alias "$CONTROLLER_NAME" \
            --env "CONTROLLER_NAME=$CONTROLLER_NAME" \
            --env "CONTROLLER_UDP_PORT=$CONTROLLER_UDP_PORT" \
            --mount "type=bind,source=$controller_dir/logs,target=/logs" \
            "$CONTROLLER_IMAGE" >/dev/null
    fi
    echo "Started $controller controller container '$CONTROLLER_CONTAINER_NAME'."
}

start() {
    local controller
    start_obc
    for controller in "${CONTROLLERS[@]}"; do
        start_controller "$controller"
    done
}

# Stop gracefully before removing.  `docker rm --force` sends SIGKILL, which
# skips each component's signal handler and so destroys the shutdown evidence
# that Phase 6 fault attribution and Phase 7 recovery depend on.
remove_container() {
    local container_name="$1"
    if container_exists "$container_name"; then
        if container_running "$container_name"; then
            docker stop --timeout "$CONTAINER_STOP_TIMEOUT_SECONDS" "$container_name" >/dev/null
        fi
        docker rm --force "$container_name" >/dev/null
        echo "Removed container '$container_name'."
    fi
}

stop() {
    local controller
    require_docker
    remove_container "$OBC_CONTAINER_NAME"
    for controller in "${CONTROLLERS[@]}"; do
        load_controller_config "$controller"
        remove_container "$CONTROLLER_CONTAINER_NAME"
    done
    if docker network inspect "$ICARUS_NETWORK_NAME" >/dev/null 2>&1; then
        docker network rm "$ICARUS_NETWORK_NAME" >/dev/null
        echo "Removed private Docker network '$ICARUS_NETWORK_NAME'."
    fi
}

status_one() {
    local container_name="$1"
    if container_exists "$container_name"; then
        docker ps --all --filter "name=^/${container_name}$" \
            --format '{{.Names}}\t{{.Status}}\t{{.Image}}'
    else
        printf '%s\t%s\t%s\n' "$container_name" 'not-created' '-'
    fi
}

status() {
    local controller
    require_docker
    printf 'NAME\tSTATUS\tIMAGE\n'
    status_one "$OBC_CONTAINER_NAME"
    for controller in "${CONTROLLERS[@]}"; do
        load_controller_config "$controller"
        status_one "$CONTROLLER_CONTAINER_NAME"
    done
}

logs() {
    local component="${1:-obc}"
    local log_file
    case "$component" in
        obc) log_file="$OBC_LOG_DIR/cfe-console.log" ;;
        adcs|payload|comms) log_file="$ROOT_DIR/controllers/$component/logs/controller.log" ;;
        *)
            echo "Unknown log component '$component'. Use obc, adcs, payload, or comms." >&2
            exit 2
            ;;
    esac
    if [ ! -f "$log_file" ]; then
        echo "No log for '$component' exists yet. Start the relevant container first." >&2
        exit 1
    fi
    # -f/-n short options are accepted by both GNU and BSD tail; run.sh runs on
    # the developer host, which may be macOS.
    tail -f -n 100 "$log_file"
}

clean_logs() {
    local controller
    ensure_log_dirs
    find "$OBC_LOG_DIR" -mindepth 1 -maxdepth 1 -type f ! -name '.gitkeep' -delete
    for controller in "${CONTROLLERS[@]}"; do
        find "$ROOT_DIR/controllers/$controller/logs" -mindepth 1 -maxdepth 1 -type f ! -name '.gitkeep' -delete
    done
    echo "Cleared generated ICARUS logs."
}

verify_phase_1() {
    local console_log="$OBC_LOG_DIR/cfe-console.log"
    local verification_log="$OBC_LOG_DIR/phase-1-verification.log"
    local evs_log="$OBC_LOG_DIR/cfe-evs.log"
    local deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))

    : >"$verification_log"
    echo "Phase 1 verification started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$verification_log"

    while [ "$SECONDS" -lt "$deadline" ]; do
        if [ -f "$console_log" ] \
            && grep -Fq 'CFE_ES_Main entering OPERATIONAL state' "$console_log"; then
            grep -E 'CFE_(EVS|ES)_' "$console_log" >"$evs_log" || true
            echo "PASS: cFE entered OPERATIONAL state." | tee -a "$verification_log"
            return 0
        fi

        if ! container_running "$OBC_CONTAINER_NAME"; then
            echo "FAIL: OBC container stopped before cFE reached OPERATIONAL state." | tee -a "$verification_log" >&2
            return 1
        fi
        sleep 1
    done

    echo "FAIL: cFE did not enter OPERATIONAL state within ${OBC_STARTUP_TIMEOUT_SECONDS}s." | tee -a "$verification_log" >&2
    return 1
}

phase_1() {
    stop
    clean_logs
    build
    start_obc
    verify_phase_1
}

verify_phase_2() {
    local controller
    local phase_log="$OBC_LOG_DIR/phase-2-verification.log"
    : >"$phase_log"
    echo "Phase 2 verification started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$phase_log"

    verify_phase_1 | tee -a "$phase_log"

    for controller in "${CONTROLLERS[@]}"; do
        local controller_log="$ROOT_DIR/controllers/$controller/logs/controller.log"
        local deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
        load_controller_config "$controller"
        while [ "$SECONDS" -lt "$deadline" ] \
            && ! grep -Fq "$CONTROLLER_NAME START controller started; udp_port=$CONTROLLER_UDP_PORT" "$controller_log" 2>/dev/null; do
            if ! container_running "$CONTROLLER_CONTAINER_NAME"; then
                echo "FAIL: $controller controller stopped before writing its startup marker." | tee -a "$phase_log" >&2
                return 1
            fi
            sleep 1
        done
        if ! container_on_icarus_network "$CONTROLLER_CONTAINER_NAME"; then
            echo "FAIL: $controller controller is not attached to $ICARUS_NETWORK_NAME." | tee -a "$phase_log" >&2
            return 1
        fi
        if ! grep -Fq "$CONTROLLER_NAME START controller started; udp_port=$CONTROLLER_UDP_PORT" "$controller_log"; then
            echo "FAIL: $controller startup marker is missing from its persistent log." | tee -a "$phase_log" >&2
            return 1
        fi
        echo "PASS: $controller is running on $ICARUS_NETWORK_NAME with an independent log." | tee -a "$phase_log"
    done

    if ! container_on_icarus_network "$OBC_CONTAINER_NAME"; then
        echo "FAIL: OBC is not attached to $ICARUS_NETWORK_NAME." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: OBC and all controllers share only the private ICARUS network." | tee -a "$phase_log"
}

phase_2() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_2
}

load_udp_config() {
    if [ ! -f "$UDP_CONFIG_FILE" ]; then
        echo "Missing UDP endpoint configuration: $UDP_CONFIG_FILE" >&2
        exit 1
    fi
    # shellcheck source=controllers/obc/config/udp.env
    set -a
    source "$UDP_CONFIG_FILE"
    set +a
}

# udp.env is the OBC-side map; each controller's runtime.env owns its identity
# and port.  Fail loudly rather than let the two definitions drift apart.
verify_udp_endpoint_config() {
    local phase_log="$1"
    local target port_var mapped_port
    for target in $ICARUS_UDP_TARGETS; do
        port_var="ICARUS_UDP_PORT_${target}"
        mapped_port="${!port_var:-}"
        load_controller_config "$target"
        if [ -z "$mapped_port" ]; then
            echo "FAIL: udp.env has no port mapping for '$target'." | tee -a "$phase_log" >&2
            return 1
        fi
        if [ "$mapped_port" != "$CONTROLLER_UDP_PORT" ]; then
            echo "FAIL: $target port mismatch: udp.env=$mapped_port runtime.env=$CONTROLLER_UDP_PORT." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: udp.env endpoint map agrees with every controller runtime.env." | tee -a "$phase_log"
}

# Runs the OBC-hosted probe against one controller and proves the exchange from
# both ends: the probe's own result, the controller's RX/TX evidence, and the
# absence of that token anywhere else.
verify_udp_route() {
    local target="$1"
    local phase_log="$2"
    local port_var="ICARUS_UDP_PORT_${target}"
    local port="${!port_var}"
    local token="${ICARUS_UDP_TOKEN_PREFIX}-$(date -u +%Y%m%dT%H%M%SZ)-${target}"
    local controller_log="$ROOT_DIR/controllers/$target/logs/controller.log"
    local probe_log="$OBC_LOG_DIR/udp-probe.log"
    local other other_log

    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$port" "$token" "$ICARUS_UDP_TIMEOUT_SECONDS" >/dev/null 2>&1; then
        echo "FAIL: OBC probe to $target:$port did not return a valid acknowledgement." \
            | tee -a "$phase_log" >&2
        return 1
    fi

    if ! grep -Fq "PASS target=$target:$port token=$token" "$probe_log" 2>/dev/null; then
        echo "FAIL: $target probe result missing from udp-probe.log." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! grep -Fq "$target RX" "$controller_log" 2>/dev/null \
        || ! grep -Fq "token=$token" "$controller_log"; then
        echo "FAIL: $target did not log receipt of token $token." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! grep -Fq "$target TX" "$controller_log" \
        || ! grep -Fq "ICARUS|ACK|$token|$target" "$controller_log"; then
        echo "FAIL: $target did not log its acknowledgement for token $token." \
            | tee -a "$phase_log" >&2
        return 1
    fi

    # One app, one controller: the token must not appear on any other link.
    for other in "${CONTROLLERS[@]}"; do
        [ "$other" = "$target" ] && continue
        other_log="$ROOT_DIR/controllers/$other/logs/controller.log"
        if grep -Fq "token=$token" "$other_log" 2>/dev/null; then
            echo "FAIL: token $token leaked to the $other controller." | tee -a "$phase_log" >&2
            return 1
        fi
    done

    echo "PASS: $target round trip verified on both ends (token $token)." | tee -a "$phase_log"
}

verify_phase_3() {
    local phase_log="$OBC_LOG_DIR/phase-3-verification.log"
    local target
    : >"$phase_log"
    echo "Phase 3 verification started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$phase_log"

    # Phase 3 depends on the Phase 2 gate, so re-prove it rather than assume it.
    if ! verify_phase_2 >>"$phase_log" 2>&1; then
        echo "FAIL: the Phase 2 gate did not pass; Phase 3 cannot be evaluated." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: Phase 2 gate re-verified." | tee -a "$phase_log"

    load_udp_config
    verify_udp_endpoint_config "$phase_log" || return 1

    for target in $ICARUS_UDP_TARGETS; do
        verify_udp_route "$target" "$phase_log" || return 1
    done

    echo "PASS: all three OBC-to-controller UDP routes verified." | tee -a "$phase_log"
}

phase_3() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_3
}

ICARUS_APPS=(adcs_sim payload_sim comms_sim)

# Maps each ICARUS cFS app to the controller it is the sole client of.
app_controller() {
    case "$1" in
        adcs_sim) echo adcs ;;
        payload_sim) echo payload ;;
        comms_sim) echo comms ;;
    esac
}

# Position of a controller in CONTROLLERS, for parallel-array lookups.
controller_index() {
    local want="$1" i=0 c
    for c in "${CONTROLLERS[@]}"; do
        [ "$c" = "$want" ] && { echo "$i"; return; }
        i=$((i + 1))
    done
    echo 0
}

# PHASE 4 SKELETON SCOPE.  This checks that the three apps are integrated --
# registered, running, logging separately, holding unique IDs, and each owning
# exactly one controller route.  It does NOT check the isolation behaviour the
# full Phase 4 gate requires (disable one app, confirm the other two continue),
# because the app bodies are deliberately still skeletons.  Phase 4 therefore
# stays marked incomplete in docs/phases.md until that lands.
verify_phase_4() {
    local phase_log="$OBC_LOG_DIR/phase-4-verification.log"
    local console_log="$OBC_LOG_DIR/cfe-console.log"
    local app app_upper app_log controller deadline

    : >"$phase_log"
    echo "Phase 4 skeleton-integration check started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$phase_log"

    # Depends on the Phase 3 gate, so re-prove it rather than assume it.
    if ! verify_phase_3 >>"$phase_log" 2>&1; then
        echo "FAIL: the Phase 3 gate did not pass; Phase 4 cannot be evaluated." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: Phase 3 gate re-verified." | tee -a "$phase_log"

    for app in "${ICARUS_APPS[@]}"; do
        app_upper="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
        app_log="$OBC_LOG_DIR/$app.log"
        controller="$(app_controller "$app")"

        # 1. The module was loaded by ES from its own shared object.
        if ! grep -Fq "Loading file: /cf/$app.so, APP: $app_upper" "$console_log"; then
            echo "FAIL: $app was not loaded as its own cFS module." | tee -a "$phase_log" >&2
            return 1
        fi

        # 2. It emitted its startup hello.
        deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
        while [ "$SECONDS" -lt "$deadline" ] \
            && ! grep -Fq "$app_upper: hello world from" "$console_log"; do
            sleep 1
        done
        if ! grep -Fq "$app_upper: hello world from" "$console_log"; then
            echo "FAIL: $app did not emit its startup hello event." | tee -a "$phase_log" >&2
            return 1
        fi

        # 3. It did not exit or fail to initialise.
        if grep -Fq "Application $app_upper called CFE_ES_ExitApp" "$console_log"; then
            echo "FAIL: $app exited instead of staying resident." | tee -a "$phase_log" >&2
            return 1
        fi

        # 4. The splitter produced its own log, carrying only its own events.
        if [ ! -s "$app_log" ]; then
            echo "FAIL: $app has no separate log file." | tee -a "$phase_log" >&2
            return 1
        fi
        local foreign
        foreign=$(grep -cE "$(printf '%s' "${ICARUS_APPS[*]}" | tr ' ' '\n' \
            | grep -v "^$app$" | tr '[:lower:]' '[:upper:]' | paste -sd'|' -)" "$app_log" || true)
        if [ "$foreign" != "0" ]; then
            echo "FAIL: $app.log contains $foreign event(s) from another app." | tee -a "$phase_log" >&2
            return 1
        fi

        # 5. It greeted its own controller, and only its own.
        if ! grep -Fq "payload=ICARUS|HELLO|$app" "$ROOT_DIR/controllers/$controller/logs/controller.log"; then
            echo "FAIL: $controller did not receive the hello from $app." | tee -a "$phase_log" >&2
            return 1
        fi
        local other
        for other in "${CONTROLLERS[@]}"; do
            [ "$other" = "$controller" ] && continue
            if grep -Fq "HELLO|$app" "$ROOT_DIR/controllers/$other/logs/controller.log" 2>/dev/null; then
                echo "FAIL: $app addressed the $other controller, which it does not own." \
                    | tee -a "$phase_log" >&2
                return 1
            fi
        done

        echo "PASS: $app registered, said hello, logs separately, and owns only $controller." \
            | tee -a "$phase_log"
    done

    verify_phase_4_unique_ids "$phase_log" || return 1

    echo "PASS: all three ICARUS apps are integrated as separate cFS applications." | tee -a "$phase_log"

    verify_phase_4_isolation "$phase_log" || return 1

    echo "PASS: Phase 4 gate complete -- three isolated cFS apps, each owning one controller." \
        | tee -a "$phase_log"
    echo "NOTE: app function bodies remain deliberate skeletons; the gate proves" | tee -a "$phase_log"
    echo "      integration and isolation, not subsystem behaviour." | tee -a "$phase_log"
}

# Topic-ID and event-ID blocks must not overlap, or two apps could collide on
# the Software Bus or become indistinguishable in the logs.
verify_phase_4_unique_ids() {
    local phase_log="$1"
    local app ids all_ids dupes

    all_ids=""
    for app in "${ICARUS_APPS[@]}"; do
        ids=$(grep -hoE '^#define DEFAULT_[A-Z_]+_TOPICID +0x[0-9A-Fa-f]+' \
            "$ROOT_DIR/apps/$app/fsw/inc/${app}_topicids.h" | awk '{print tolower($3)}')
        if [ -z "$ids" ]; then
            echo "FAIL: $app declares no topic IDs." | tee -a "$phase_log" >&2
            return 1
        fi
        all_ids="$all_ids$ids
"
    done

    dupes=$(printf '%s' "$all_ids" | grep -v '^$' | sort | uniq -d)
    if [ -n "$dupes" ]; then
        echo "FAIL: topic IDs are shared between apps: $(printf '%s' "$dupes" | tr '\n' ' ')" \
            | tee -a "$phase_log" >&2
        return 1
    fi

    # Event IDs are namespaced per app by EVS, but ICARUS also gives each app a
    # distinct numeric base so an event ID alone identifies its origin.
    local bases
    bases=$(grep -hoE '^#define [A-Z_]+_EID_BASE +[0-9]+' \
        "$ROOT_DIR"/apps/*/fsw/inc/*_eventids.h | awk '{print $3}' | sort)
    # Both sides use printf '%s\n' so the trailing newline is present either
    # way; mixing '%s' with sort's own trailing newline miscounts by one.
    if [ "$(printf '%s\n' "$bases" | sort -u | wc -l | tr -d ' ')" \
         != "$(printf '%s\n' "$bases" | wc -l | tr -d ' ')" ]; then
        echo "FAIL: two apps share an event-ID base." | tee -a "$phase_log" >&2
        return 1
    fi

    echo "PASS: topic-ID and event-ID blocks are unique across all three apps." | tee -a "$phase_log"
}

# Counts lines currently in a log, so later assertions can look only at output
# produced after this point.  The /logs mount persists across OBC restarts, so
# without this an assertion would match the previous run's evidence.
log_mark() {
    [ -f "$1" ] && wc -l <"$1" | tr -d ' ' || echo 0
}

# Everything a log gained after the given mark.
log_since() {
    local file="$1" mark="$2"
    [ -f "$file" ] && tail -n "+$((mark + 1))" "$file" || true
}

# Closes the Phase 4 gate's isolation requirement: disabling one app must affect
# only that app and its own controller link.  The OBC is restarted with one app
# dropped from the startup script; the other two must keep running, keep
# producing scheduled wakeups, and keep their controller routes.
verify_phase_4_isolation() {
    local phase_log="$1"
    local disabled="adcs_sim"
    local disabled_ctrl="adcs"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local console_mark deadline app app_upper other beats idx
    # Indexed arrays only: macOS ships bash 3.2, which has no associative arrays.
    local ctrl_marks=()

    echo "Isolation check: restarting the OBC with $disabled disabled." | tee -a "$phase_log"

    console_mark=$(log_mark "$console")
    for other in "${CONTROLLERS[@]}"; do
        ctrl_marks+=("$(log_mark "$ROOT_DIR/controllers/$other/logs/controller.log")")
    done

    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    ICARUS_DISABLED_APPS="$disabled" start_obc >/dev/null

    # Wait for cFE to come back up, then long enough for at least one scheduled
    # wakeup from each surviving app. payload_sim is the 1 Hz app and so the
    # fastest reliable signal; comms_sim is 0.1 Hz and OSAL's console delivers
    # in bursts, so this needs a generous deadline rather than a tight one.
    deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ] \
        && ! log_since "$console" "$console_mark" | grep -Fq 'CFE_ES_Main entering OPERATIONAL state'; do
        sleep 1
    done
    if ! log_since "$console" "$console_mark" | grep -Fq 'CFE_ES_Main entering OPERATIONAL state'; then
        echo "FAIL: OBC did not reach OPERATIONAL with $disabled disabled." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: cFE still reaches OPERATIONAL with $disabled absent." | tee -a "$phase_log"

    deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ]; do
        beats=$(log_since "$console" "$console_mark" | grep -c 'COMMS_SIM: wakeup' || true)
        [ "${beats:-0}" -ge 1 ] && break
        sleep 2
    done

    # 1. The disabled app really is gone.
    if log_since "$console" "$console_mark" | grep -Fq "Loading file: /cf/$disabled.so"; then
        echo "FAIL: $disabled was still loaded despite being disabled." | tee -a "$phase_log" >&2
        return 1
    fi
    app_upper="$(printf '%s' "$disabled" | tr '[:lower:]' '[:upper:]')"
    if [ "$(log_since "$console" "$console_mark" | grep -c "$app_upper: wakeup" || true)" != "0" ]; then
        echo "FAIL: $disabled produced scheduled wakeups while disabled." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $disabled is absent -- not loaded and silent." | tee -a "$phase_log"

    # 2. Its controller sees no new traffic, because nothing else owns that route.
    idx=$(controller_index "$disabled_ctrl")
    if log_since "$ROOT_DIR/controllers/$disabled_ctrl/logs/controller.log" \
        "${ctrl_marks[$idx]}" | grep -Fq "HELLO|$disabled"; then
        echo "FAIL: $disabled_ctrl received a hello although $disabled was disabled." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: the $disabled_ctrl route is quiet, and no other app took it over." | tee -a "$phase_log"

    # 3. The unrelated apps are unaffected: loaded, waking, routes alive.
    for app in "${ICARUS_APPS[@]}"; do
        [ "$app" = "$disabled" ] && continue
        app_upper="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
        other="$(app_controller "$app")"

        if ! log_since "$console" "$console_mark" | grep -Fq "Loading file: /cf/$app.so"; then
            echo "FAIL: $app did not load after $disabled was disabled." | tee -a "$phase_log" >&2
            return 1
        fi
        beats=$(log_since "$console" "$console_mark" | grep -c "$app_upper: wakeup" || true)
        if [ "${beats:-0}" -lt 1 ]; then
            echo "FAIL: $app stopped producing scheduled wakeups after $disabled was disabled." \
                | tee -a "$phase_log" >&2
            return 1
        fi
        idx=$(controller_index "$other")
        if ! log_since "$ROOT_DIR/controllers/$other/logs/controller.log" \
            "${ctrl_marks[$idx]}" | grep -Fq "HELLO|$app"; then
            echo "FAIL: $app lost its $other route after $disabled was disabled." | tee -a "$phase_log" >&2
            return 1
        fi
        echo "PASS: $app unaffected -- loaded, $beats wakeup(s), $other route alive." \
            | tee -a "$phase_log"
    done

    # 4. Restore, so the phase leaves a complete system behind.
    console_mark=$(log_mark "$console")
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    start_obc >/dev/null
    deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ] \
        && [ "$(log_since "$console" "$console_mark" | grep -c 'hello world from' || true)" -lt 3 ]; do
        sleep 1
    done
    if [ "$(log_since "$console" "$console_mark" | grep -c 'hello world from' || true)" -lt 3 ]; then
        echo "FAIL: all three apps did not return after re-enabling $disabled." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: all three apps restored after re-enabling $disabled." | tee -a "$phase_log"
}

phase_4() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_4
}

# Phase 5 declared rates, in millihertz, matching each app's
# <APP>_DECLARED_RATE_MHZ and its PacketRate in the mission schedule table.
PHASE5_RATE_adcs_sim=10000     # 10 Hz
PHASE5_RATE_payload_sim=1000   # 1 Hz
PHASE5_RATE_comms_sim=100      # 0.1 Hz

# Interval samples required per app after the warm-up sample is discarded.
PHASE5_MIN_SAMPLES=10

# Mean-rate tolerance, percent. Declared tolerance for the gate.
PHASE5_MEAN_TOL_PCT=5

# Generous: the slowest app ticks every 10s so 12 markers needs ~120s, and
# OSAL's async console can delay delivery by tens of seconds on top of that.
PHASE5_COLLECT_TIMEOUT_SECONDS=420

app_declared_rate_mhz() {
    eval "printf '%s' \"\${PHASE5_RATE_$1}\""
}

# Markers produced by the CURRENT OBC run only.
#
# The log outlives the container, and Phase 4's isolation check restarts the
# OBC twice, so the file holds several runs. Sequence numbers restart at 1 each
# boot, so the last marker's seq is exactly the current run's count -- which is
# the segment the rate checker measures. Counting every line in the file would
# overcount and let the collection loop finish early.
marker_count() {
    local last
    if [ ! -f "$1" ]; then
        echo 0
        return
    fi
    last=$(grep -oE 'wakeup seq=[0-9]+' "$1" 2>/dev/null | tail -n 1 | cut -d= -f2)
    echo "${last:-0}"
}

verify_phase_5() {
    local phase_log="$OBC_LOG_DIR/phase-5-verification.log"
    local app app_log rate needed deadline count ready all_ready
    : >"$phase_log"
    echo "Phase 5 verification started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$phase_log"

    # Depends on the Phase 4 gate, so re-prove it rather than assume it.
    if ! verify_phase_4 >>"$phase_log" 2>&1; then
        echo "FAIL: the Phase 4 gate did not pass; Phase 5 cannot be evaluated." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: Phase 4 gate re-verified." | tee -a "$phase_log"

    # One warm-up interval is discarded, so collect two extra markers.
    needed=$((PHASE5_MIN_SAMPLES + 2))
    echo "Collecting at least $needed wakeup markers per app (this takes a few minutes)." \
        | tee -a "$phase_log"

    deadline=$((SECONDS + PHASE5_COLLECT_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ]; do
        all_ready=1
        for app in "${ICARUS_APPS[@]}"; do
            count=$(marker_count "$OBC_LOG_DIR/$app.log")
            [ "$count" -lt "$needed" ] && all_ready=0
        done
        [ "$all_ready" = "1" ] && break
        sleep 5
    done

    for app in "${ICARUS_APPS[@]}"; do
        count=$(marker_count "$OBC_LOG_DIR/$app.log")
        echo "  $app: $count marker(s) collected" | tee -a "$phase_log"
        if [ "$count" -lt "$needed" ]; then
            echo "FAIL: $app produced only $count marker(s); needed $needed within ${PHASE5_COLLECT_TIMEOUT_SECONDS}s." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done

    # EVS rate-limits each app to 15 events/sec. The 10 Hz app sits at 10, so a
    # squelch here means markers were dropped and any rate figure is unsound.
    if grep -Fq 'Events squelched' "$OBC_LOG_DIR/cfe-console.log"; then
        echo "FAIL: EVS squelched events; wakeup markers were dropped." | tee -a "$phase_log" >&2
        grep -F 'Events squelched' "$OBC_LOG_DIR/cfe-console.log" | head -3 | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: no EVS squelching, so no wakeup markers were dropped." | tee -a "$phase_log"

    # The checker runs ON the OBC, against the MET embedded in each marker.
    for app in "${ICARUS_APPS[@]}"; do
        rate=$(app_declared_rate_mhz "$app")
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-rate-check \
            "/logs/$app.log" "$rate" "$PHASE5_MIN_SAMPLES" "$PHASE5_MEAN_TOL_PCT" \
            2>&1 | tee -a "$phase_log"; then
            echo "FAIL: $app did not hold its declared rate." | tee -a "$phase_log" >&2
            return 1
        fi
    done

    echo "PASS: all three apps held their declared SCH rates within +/-${PHASE5_MEAN_TOL_PCT}% mean." \
        | tee -a "$phase_log"
}

phase_5() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_5
}

# --- Phase 6: fault observation and containment ---------------------------
#
# Phase 6 OBSERVES faults; it does not recover from them. Every HS action is
# HS_AMTActType_EVENT ("report, do not act"); recovery is Phase 7.
#
# NOT demonstrable in this container, and deliberately not claimed by this
# gate: CPU-hogging detection and HS watchdog arming. Both live inside the
# HS_AppInit block that the linux_sysmon failure skips. See
# docs/cfs-notes.md#hs-system-monitor-fails-in-a-container.

# ci_lab command MIDs. The app wakeup/command MIDs derive from each app's
# topic-ID block: command MID = 0x1800 | topic.
PHASE6_CMD_MID_adcs_sim=0x18c0
PHASE6_INJECT_STALL_CC=3

# HS detection window is AMT CycleCount (20) x the HS cycle (1.0s, pinned by
# the HS_WAKEUP entry in sch_lab_table.c), so ~20s. Allow generous headroom.
PHASE6_DETECT_TIMEOUT_SECONDS=90

app_cmd_mid() {
    eval "printf '%s' \"\${PHASE6_CMD_MID_$1}\""
}

# Waits for a string to appear in a log after a recorded mark, bounded.
wait_for_marker() {
    local file="$1" mark="$2" needle="$3" timeout="$4" deadline
    deadline=$((SECONDS + timeout))
    while [ "$SECONDS" -lt "$deadline" ]; do
        if log_since "$file" "$mark" | grep -Fq "$needle"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

verify_phase_6() {
    local phase_log="$OBC_LOG_DIR/phase-6-verification.log"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local mark app other p idx
    : >"$phase_log"
    echo "Phase 6 verification started at $(date -u +%Y-%m-%dT%H:%M:%SZ)." | tee -a "$phase_log"

    if ! verify_phase_5 >>"$phase_log" 2>&1; then
        echo "FAIL: the Phase 5 gate did not pass; Phase 6 cannot be evaluated." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: Phase 5 gate re-verified." | tee -a "$phase_log"

    # HS must actually be monitoring, or every later assertion is vacuous.
    if grep -Fq 'Application Monitoring Disabled' "$console"; then
        echo "FAIL: HS application monitoring is disabled; the AMT was rejected." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    if ! grep -Eq 'AppMon verify results: good = 3, bad = 0' "$console"; then
        echo "FAIL: HS did not validate exactly 3 ICARUS app-monitor entries." \
            | tee -a "$phase_log" >&2
        grep -F 'AppMon verify results' "$console" | tail -2 | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: HS loaded the ICARUS app monitor table (3 good, 0 bad)." | tee -a "$phase_log"

    verify_phase_6_app_stall "$phase_log" || return 1
    verify_phase_6_app_exit "$phase_log" || return 1
    verify_phase_6_controller_stop "$phase_log" || return 1
    verify_phase_6_controller_disconnect "$phase_log" || return 1
    verify_phase_6_malformed_udp "$phase_log" || return 1
    verify_phase_6_log_mount "$phase_log" || return 1

    echo "PASS: all six faults were detected, attributed, and contained." | tee -a "$phase_log"
    echo "NOTE: CPU-hog detection and HS watchdog arming are unavailable in this" | tee -a "$phase_log"
    echo "      container and are explicitly NOT claimed by this gate." | tee -a "$phase_log"
}

# FAULT 1: an app alive but no longer doing its work.
verify_phase_6_app_stall() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local app=adcs_sim app_upper=ADCS_SIM mark other

    echo "--- Fault 1: app heartbeat stall ($app) ---" | tee -a "$phase_log"
    mark=$(log_mark "$console")

    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$(app_cmd_mid $app)" "$PHASE6_INJECT_STALL_CC" >/dev/null 2>&1 || {
        echo "FAIL: could not send the stall command through ci_lab." | tee -a "$phase_log" >&2
        return 1
    }

    if ! wait_for_marker "$console" "$mark" "$app_upper: SIMULATED FAULT" 30; then
        echo "FAIL: $app never acknowledged the injected stall." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $app acknowledged the injected stall (source is traceable)." | tee -a "$phase_log"

    if ! wait_for_marker "$console" "$mark" \
        "App Monitor Failure: APP:($app_upper): Action: Event Only" \
        "$PHASE6_DETECT_TIMEOUT_SECONDS"; then
        echo "FAIL: HS did not detect the $app stall within ${PHASE6_DETECT_TIMEOUT_SECONDS}s." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: HS detected the $app stall and reported without acting." | tee -a "$phase_log"

    # It must be a stall, not an exit.
    if log_since "$console" "$mark" | grep -Fq "Application $app_upper called CFE_ES_ExitApp"; then
        echo "FAIL: $app exited; this fault is supposed to leave it loaded." | tee -a "$phase_log" >&2
        return 1
    fi

    # Containment: no HS failure for the other two, and their routes live.
    for other in payload_sim comms_sim; do
        local other_upper
        other_upper="$(printf '%s' "$other" | tr '[:lower:]' '[:upper:]')"
        if log_since "$console" "$mark" | grep -Fq "App Monitor Failure: APP:($other_upper)"; then
            echo "FAIL: HS also reported $other; the fault was not contained." \
                | tee -a "$phase_log" >&2
            return 1
        fi
        local ctrl port
        ctrl="$(app_controller "$other")"
        eval "port=\${PHASE5_RATE_$other:-}" >/dev/null 2>&1 || true
        idx=$(controller_index "$ctrl")
        load_controller_config "$ctrl"
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
            "$ctrl" "$CONTROLLER_UDP_PORT" "p6stall-$ctrl" 3 >/dev/null 2>&1; then
            echo "FAIL: $other lost its $ctrl route during the $app stall." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: the other two apps and their controller routes were unaffected." | tee -a "$phase_log"
}
# FAULT 2: an app told to exit through the real ES ground command.
#
# The OBC is restarted first because AMT countdowns are ONE-SHOT: an entry
# fires once per table load and is not re-armed, so without a fresh boot the
# fault-1 detection would be the only one HS ever reports.
verify_phase_6_app_exit() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local app=payload_sim app_upper=PAYLOAD_SIM mark

    echo "--- Fault 2: app controlled exit ($app) ---" | tee -a "$phase_log"
    echo "Restarting the OBC to re-arm the one-shot HS app monitors." | tee -a "$phase_log"

    mark=$(log_mark "$console")
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    start_obc >/dev/null
    if ! wait_for_marker "$console" "$mark" 'CFE_ES_Main entering OPERATIONAL state' \
        "$OBC_STARTUP_TIMEOUT_SECONDS"; then
        echo "FAIL: OBC did not come back up for the app-exit fault." | tee -a "$phase_log" >&2
        return 1
    fi

    mark=$(log_mark "$console")

    # CFE_ES_STOP_APP. MID 0x1806 = 0x1800 | ES command topic 6;
    # CFE_ES_FunctionCode_STOP_APP is 5 (not 4 -- 4 is unused here).
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        0x1806 5 "$app_upper" >/dev/null 2>&1 || {
        echo "FAIL: could not send CFE_ES_STOP_APP through ci_lab." | tee -a "$phase_log" >&2
        return 1
    }

    if ! wait_for_marker "$console" "$mark" "Stop Application $app_upper" 60 \
        && ! wait_for_marker "$console" "$mark" "Application $app_upper called CFE_ES_ExitApp" 30; then
        echo "FAIL: $app did not exit in response to CFE_ES_STOP_APP." | tee -a "$phase_log" >&2
        log_since "$console" "$mark" | grep -iE "ES_|CI_LAB" | tail -5 | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $app exited on the ES ground command (source is traceable)." | tee -a "$phase_log"

    if ! wait_for_marker "$console" "$mark" "APP:($app_upper)" \
        "$PHASE6_DETECT_TIMEOUT_SECONDS"; then
        echo "FAIL: HS did not report the missing $app within ${PHASE6_DETECT_TIMEOUT_SECONDS}s." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: HS detected that $app is gone." | tee -a "$phase_log"

    # Containment: cFE itself and the other apps survive an app exiting.
    if ! container_running "$OBC_CONTAINER_NAME"; then
        echo "FAIL: the OBC died when one app exited." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! log_since "$console" "$mark" | grep -Fq 'ADCS_SIM: wakeup'; then
        echo "FAIL: adcs_sim stopped working after $app exited." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: cFE and the unrelated apps survived the exit." | tee -a "$phase_log"
}

# FAULT 3: a controller container stopped outright.
verify_phase_6_controller_stop() {
    local phase_log="$1"
    local target=adcs rc

    echo "--- Fault 3: controller stopped ($target) ---" | tee -a "$phase_log"
    load_controller_config "$target"
    docker stop --timeout "$CONTAINER_STOP_TIMEOUT_SECONDS" "$CONTROLLER_CONTAINER_NAME" >/dev/null

    # Docker withdraws the alias on stop, so this surfaces as resolve-failed
    # (exit 5) rather than a timeout. See docs/peripherals.md.
    rc=0
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p6stop" 3 >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "0" ]; then
        echo "FAIL: the $target route still answered after the container was stopped." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: the $target route is down and the failure is reported (probe rc=$rc)." \
        | tee -a "$phase_log"

    local other
    for other in payload comms; do
        load_controller_config "$other"
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
            "$other" "$CONTROLLER_UDP_PORT" "p6stop-$other" 3 >/dev/null 2>&1; then
            echo "FAIL: the $other route broke when $target was stopped." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    if ! container_running "$OBC_CONTAINER_NAME"; then
        echo "FAIL: the OBC died when a controller stopped." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: the other two routes and the OBC continued." | tee -a "$phase_log"

    load_controller_config "$target"
    docker start "$CONTROLLER_CONTAINER_NAME" >/dev/null
    echo "Restored the $target controller." | tee -a "$phase_log"
}

# FAULT 4: a controller alive but unreachable. Distinct from fault 3 -- the
# alias still resolves, so this must present as a TIMEOUT, not resolve-failed.
verify_phase_6_controller_disconnect() {
    local phase_log="$1"
    local target=comms rc

    echo "--- Fault 4: controller UDP disconnect ($target) ---" | tee -a "$phase_log"
    load_controller_config "$target"
    docker network disconnect "$ICARUS_NETWORK_NAME" "$CONTROLLER_CONTAINER_NAME" >/dev/null 2>&1 || {
        echo "FAIL: could not detach $target from $ICARUS_NETWORK_NAME." | tee -a "$phase_log" >&2
        return 1
    }

    rc=0
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p6disc" 3 >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "0" ]; then
        echo "FAIL: the $target route answered while detached from the network." \
            | tee -a "$phase_log" >&2
        docker network connect "$ICARUS_NETWORK_NAME" "$CONTROLLER_CONTAINER_NAME" >/dev/null 2>&1 || true
        return 1
    fi
    if ! container_running "$CONTROLLER_CONTAINER_NAME"; then
        echo "FAIL: $target died from being detached; it should stay alive but unreachable." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $target is alive but unreachable (probe rc=$rc), a distinct signature from a stop." \
        | tee -a "$phase_log"

    docker network connect "$ICARUS_NETWORK_NAME" "$CONTROLLER_CONTAINER_NAME" >/dev/null 2>&1 || true
    echo "Reattached $target to $ICARUS_NETWORK_NAME." | tee -a "$phase_log"
}

# FAULT 5: malformed and oversized input. The rejection logic was implemented
# and negative-tested in Phase 3, so this asserts it rather than adding code.
verify_phase_6_malformed_udp() {
    local phase_log="$1"
    local target=payload reason mark log

    echo "--- Fault 5: malformed and oversized UDP input ($target) ---" | tee -a "$phase_log"
    load_controller_config "$target"
    log="$ROOT_DIR/controllers/$target/logs/controller.log"
    mark=$(log_mark "$log")

    docker exec "$OBC_CONTAINER_NAME" bash -c \
        "echo -n 'GARBAGE-NOT-ICARUS' > /dev/udp/$target/$CONTROLLER_UDP_PORT" 2>/dev/null || true
    docker exec "$OBC_CONTAINER_NAME" bash -c \
        "head -c 900 /dev/zero | tr '\\0' 'A' > /dev/udp/$target/$CONTROLLER_UDP_PORT" 2>/dev/null || true
    docker exec "$OBC_CONTAINER_NAME" bash -c \
        "printf 'ICARUS|HELLO|\\x01\\x02' > /dev/udp/$target/$CONTROLLER_UDP_PORT" 2>/dev/null || true
    docker exec "$OBC_CONTAINER_NAME" bash -c \
        "echo -n 'ICARUS|HELLO|' > /dev/udp/$target/$CONTROLLER_UDP_PORT" 2>/dev/null || true

    for reason in bad-prefix oversize non-printable bad-token; do
        if ! wait_for_marker "$log" "$mark" "reason=$reason" 20; then
            echo "FAIL: $target did not log a '$reason' rejection." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: $target logged all four rejection reasons." | tee -a "$phase_log"

    if [ "$(docker inspect -f '{{.RestartCount}}' "$CONTROLLER_CONTAINER_NAME")" != "0" ]; then
        echo "FAIL: $target restarted; malformed input must not kill it." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p6recover" 3 >/dev/null 2>&1; then
        echo "FAIL: $target stopped serving valid traffic after malformed input." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    if ! container_running "$OBC_CONTAINER_NAME"; then
        echo "FAIL: the OBC died from sending malformed input." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $target survived and still serves valid traffic; cFE unaffected." | tee -a "$phase_log"
}
# FAULT 6: an unavailable log mount, on a controller AND on the OBC.
#
# Both must degrade rather than die: the process keeps running and keeps
# emitting on stdout, where `docker logs` still captures it. Losing the file is
# an observable degradation, not an outage.
verify_phase_6_log_mount() {
    local phase_log="$1"
    local target=comms out

    echo "--- Fault 6: unavailable log mount ---" | tee -a "$phase_log"

    # --- controller, with /logs present but unwritable ---
    #
    # A READ-ONLY tmpfs, and specifically not either of two things that look
    # equivalent but inject nothing:
    #   - omitting the bind mount: the controller image creates /logs at build
    #     time, so the directory is still there and perfectly writable;
    #   - tmpfs-mode=0555: the container runs as root, which bypasses
    #     permission bits via CAP_DAC_OVERRIDE and writes anyway.
    # Only the readonly mount flag actually blocks the write.
    load_controller_config "$target"
    remove_container "$CONTROLLER_CONTAINER_NAME" >/dev/null
    docker run --detach \
        --name "$CONTROLLER_CONTAINER_NAME" \
        --network "$ICARUS_NETWORK_NAME" \
        --network-alias "$CONTROLLER_NAME" \
        --env "CONTROLLER_NAME=$CONTROLLER_NAME" \
        --env "CONTROLLER_UDP_PORT=$CONTROLLER_UDP_PORT" \
        --mount "type=tmpfs,destination=/logs,readonly" \
        "$CONTROLLER_IMAGE" >/dev/null

    local deadline=$((SECONDS + 30))
    while [ "$SECONDS" -lt "$deadline" ] \
        && ! docker logs "$CONTROLLER_CONTAINER_NAME" 2>&1 | grep -Fq 'LISTEN bound udp'; do
        sleep 2
    done
    out=$(docker logs "$CONTROLLER_CONTAINER_NAME" 2>&1 || true)
    if ! printf '%s' "$out" | grep -Fq 'LISTEN bound udp'; then
        echo "FAIL: $target did not start without a log mount." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! printf '%s' "$out" | grep -Fiq 'cannot open /logs'; then
        echo "FAIL: $target did not report the unavailable log file." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! container_running "$CONTROLLER_CONTAINER_NAME"; then
        echo "FAIL: $target died without a log mount." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p6nolog" 3 >/dev/null 2>&1; then
        echo "FAIL: $target stopped serving traffic without a log mount." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $target reported the missing log mount, stayed alive, and kept serving." \
        | tee -a "$phase_log"

    # restore the controller with its mount
    remove_container "$CONTROLLER_CONTAINER_NAME" >/dev/null
    start_controller "$target" >/dev/null

    # --- OBC, with a read-only /logs mount ---
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    docker run --detach \
        --name "$OBC_CONTAINER_NAME" \
        --sysctl fs.mqueue.msg_max=64 \
        --network "$ICARUS_NETWORK_NAME" \
        --network-alias obc \
        --mount "type=bind,source=$OBC_LOG_DIR,target=/logs,readonly" \
        "$OBC_IMAGE" >/dev/null

    #
    # Evidence must be latched AS IT APPEARS, not re-read after the wait.
    # With file logging unavailable the 10 Hz app floods container stdout, and
    # Docker's log rotation discards the early lines -- so by the end of the
    # wait both the WARNING and the OPERATIONAL line have been rotated out of
    # `docker logs` even though they were printed. Re-reading at the end made
    # this test fail against a perfectly healthy OBC.
    local seen_warn=0 seen_oper=0
    deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ]; do
        out=$(docker logs "$OBC_CONTAINER_NAME" 2>&1 || true)
        case "$out" in
            *"unavailable or unwritable"*) seen_warn=1 ;;
        esac
        case "$out" in
            *"CFE_ES_Main entering OPERATIONAL state"*) seen_oper=1 ;;
        esac
        [ "$seen_warn" = "1" ] && [ "$seen_oper" = "1" ] && break
        sleep 2
    done

    if [ "$seen_warn" != "1" ]; then
        echo "FAIL: the OBC did not report the unwritable log mount." | tee -a "$phase_log" >&2
        return 1
    fi
    if [ "$seen_oper" != "1" ]; then
        echo "FAIL: the OBC did not reach OPERATIONAL with a read-only log mount." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    if ! container_running "$OBC_CONTAINER_NAME"; then
        echo "FAIL: the OBC died with an unwritable log mount." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: the OBC reported the unwritable mount and still reached OPERATIONAL." \
        | tee -a "$phase_log"

    # restore the OBC with a writable mount so the phase leaves a working system
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    start_obc >/dev/null
    deadline=$((SECONDS + OBC_STARTUP_TIMEOUT_SECONDS))
    while [ "$SECONDS" -lt "$deadline" ] \
        && ! container_running "$OBC_CONTAINER_NAME"; do
        sleep 2
    done
    if ! container_running "$OBC_CONTAINER_NAME"; then
        echo "FAIL: the OBC did not restart after the log-mount fault." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: restored the OBC with a writable log mount." | tee -a "$phase_log"
}

phase_6() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_6
}

# --- Phase 7: recovery ladder --------------------------------------------
#
# Recovery escalates app -> controller -> OBC, least disruptive first. The
# order and its rationale live in controllers/obc/config/mission/README.md.

PHASE7_ES_CMD_MID=0x1806
PHASE7_ES_RESTART_APP_CC=6

# HS app monitors are ONE-SHOT: the countdown is never rewritten by the monitor,
# so a restarted app is no longer watched. Re-arming needs DISABLE then ENABLE --
# enabling while already enabled refreshes nothing and logs "*already* Enabled".
PHASE7_HS_CMD_MID=0x18ae
PHASE7_HS_DISABLE_APPMON_CC=3
PHASE7_HS_ENABLE_APPMON_CC=2

# ES defers the restart: AppTimerMsec = APP_KILL_TIMEOUT(5) x APP_SCAN_RATE(1000)
# = 5s before it force-cancels the task, plus async-console log latency. A short
# timeout here would flake against a perfectly good restart.
PHASE7_RESTART_TIMEOUT_SECONDS=90

timeline() {
    printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" | tee -a "$2"
}

# Waits until the whole stack is nominal: cFE up and all three apps actually
# ticking. Phase 7 must start from a known-good baseline -- Phase 6 ends by
# restarting the OBC, and injecting a fault into a still-booting cFE means the
# command is dropped and the rung fails for the wrong reason.
wait_for_nominal() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local app au mark

    mark=$(log_mark "$console")
    for app in "${ICARUS_APPS[@]}"; do
        au="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
        if ! wait_for_marker "$console" "$mark" "$au: wakeup" "$OBC_STARTUP_TIMEOUT_SECONDS"; then
            echo "FAIL: $app is not running; the stack was not nominal before recovery testing." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done
    timeline "    baseline nominal: all three apps are ticking." "$phase_log"
}

verify_phase_7() {
    local phase_log="$OBC_LOG_DIR/phase-7-verification.log"
    : >"$phase_log"
    timeline "Phase 7 recovery-ladder verification started." "$phase_log"

    if ! verify_phase_6 >>"$phase_log" 2>&1; then
        echo "FAIL: the Phase 6 gate did not pass; Phase 7 cannot be evaluated." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: Phase 6 gate re-verified." | tee -a "$phase_log"

    # Phase 6 leaves the OBC freshly restarted; wait for a nominal baseline.
    wait_for_nominal "$phase_log" || return 1

    verify_phase_7_rung1_app "$phase_log" || return 1
    verify_phase_7_rung2_controller "$phase_log" || return 1
    verify_phase_7_rung3_obc "$phase_log" || return 1
    verify_phase_7_failed_recovery "$phase_log" || return 1

    echo "PASS: the recovery ladder restores nominal operation at app," | tee -a "$phase_log"
    echo "      controller and OBC scope, and a failed recovery stays visible." | tee -a "$phase_log"
}

# RUNG 1 -- recover one app with the real ES ground command.
verify_phase_7_rung1_app() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local app=adcs_sim app_upper=ADCS_SIM ctrl=adcs mark other other_upper

    timeline "--- Rung 1: app recovery ($app) ---" "$phase_log"

    # Break it first: recovery of a healthy app proves nothing.
    mark=$(log_mark "$console")
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$(app_cmd_mid $app)" "$PHASE6_INJECT_STALL_CC" >/dev/null 2>&1 || {
        echo "FAIL: could not stall $app to set up the recovery test." | tee -a "$phase_log" >&2
        return 1
    }
    if ! wait_for_marker "$console" "$mark" "$app_upper: SIMULATED FAULT" 30; then
        echo "FAIL: $app did not stall, so there is nothing to recover." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! wait_for_marker "$console" "$mark" \
        "App Monitor Failure: APP:($app_upper)" "$PHASE6_DETECT_TIMEOUT_SECONDS"; then
        echo "FAIL: HS did not report $app as degraded before recovery." | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    $app is stalled and HS has reported it degraded." "$phase_log"

    # Recover it.
    mark=$(log_mark "$console")
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$PHASE7_ES_CMD_MID" "$PHASE7_ES_RESTART_APP_CC" "$app_upper" >/dev/null 2>&1 || {
        echo "FAIL: could not send CFE_ES_RESTART_APP." | tee -a "$phase_log" >&2
        return 1
    }

    # No trailing period: the observable line is the ES SysLog variant
    # ("CFE_ES_RestartApp: Restart Application X Initiated"), not the EVS
    # DEBUG event, which is filtered out by the default event type mask.
    if ! wait_for_marker "$console" "$mark" "Restart Application $app_upper Initiated" 30; then
        echo "FAIL: ES did not accept the restart command for $app." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! wait_for_marker "$console" "$mark" "Restart Application $app_upper Completed" \
        "$PHASE7_RESTART_TIMEOUT_SECONDS"; then
        echo "FAIL: ES did not complete the restart of $app within ${PHASE7_RESTART_TIMEOUT_SECONDS}s." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    ES reported the restart of $app complete." "$phase_log"

    # ES reports "Completed" as soon as the new main task is SPAWNED -- it does
    # NOT prove the app initialised. These next three assertions are what make
    # the recovery claim real rather than cosmetic.
    if ! wait_for_marker "$console" "$mark" "$app_upper: hello world from" 60; then
        echo "FAIL: $app was restarted but never re-initialised." | tee -a "$phase_log" >&2
        return 1
    fi
    # A genuine re-init memsets the app's data, so its sequence restarts at 1.
    if ! wait_for_marker "$console" "$mark" "$app_upper: wakeup seq=1 " 60; then
        echo "FAIL: $app did not restart its wakeup sequence; state was not reset." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    # Resource reclamation: a leaked pipe name would fail Init and kill the app.
    if log_since "$console" "$mark" | grep -Fq "$app_upper: error creating SB pipe"; then
        echo "FAIL: $app could not recreate its SB pipe; resources leaked across the restart." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    local es_err
    es_err=$(log_since "$console" "$mark" | grep -cE "Restart Application $app_upper Failed|name taken" || true)
    if [ "${es_err:-0}" != "0" ]; then
        echo "FAIL: ES reported $es_err restart error(s) for $app." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $app restarted once, re-initialised, and reset its own state." | tee -a "$phase_log"

    # The fault must actually be gone -- at the declared rate, not merely present.
    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-rate-check \
        "/logs/$app.log" "$(app_declared_rate_mhz $app)" 5 5 >/dev/null 2>&1; then
        echo "FAIL: $app resumed but not at its declared rate." | tee -a "$phase_log" >&2
        return 1
    fi
    load_controller_config "$ctrl"
    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$ctrl" "$CONTROLLER_UDP_PORT" "p7rung1" 3 >/dev/null 2>&1; then
        echo "FAIL: the $ctrl route did not come back after $app recovered." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $app is back at its declared rate with its own route working." | tee -a "$phase_log"

    # Containment during recovery.
    for other in payload_sim comms_sim; do
        other_upper="$(printf '%s' "$other" | tr '[:lower:]' '[:upper:]')"
        if ! log_since "$console" "$mark" | grep -Fq "$other_upper: wakeup"; then
            echo "FAIL: $other stopped working while $app was being recovered." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: the other two apps kept running throughout the recovery." | tee -a "$phase_log"

    verify_phase_7_rearm_hs "$phase_log" || return 1
}

# HS monitors are spent once they fire; recovery is incomplete until re-armed.
verify_phase_7_rearm_hs() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local mark

    mark=$(log_mark "$console")
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$PHASE7_HS_CMD_MID" "$PHASE7_HS_DISABLE_APPMON_CC" >/dev/null 2>&1 || true
    if ! wait_for_marker "$console" "$mark" 'Application Monitoring Disabled' 30; then
        echo "FAIL: HS did not disable application monitoring for the re-arm." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$PHASE7_HS_CMD_MID" "$PHASE7_HS_ENABLE_APPMON_CC" >/dev/null 2>&1 || true
    if ! wait_for_marker "$console" "$mark" 'Application Monitoring Enabled' 30; then
        echo "FAIL: HS did not re-enable application monitoring." | tee -a "$phase_log" >&2
        return 1
    fi
    # Enabling while already enabled refreshes nothing -- that is a failed re-arm.
    if log_since "$console" "$mark" | grep -Fq 'already'; then
        echo "FAIL: HS reported monitoring was *already* enabled; the re-arm refreshed nothing." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: HS application monitoring re-armed, so the recovered app is watched again." \
        | tee -a "$phase_log"
}
# RUNG 2 -- recover one controller by restarting its container.
verify_phase_7_rung2_controller() {
    local phase_log="$1"
    local target=adcs app=adcs_sim log mark other rc pre_lines

    timeline "--- Rung 2: controller restart ($target) ---" "$phase_log"
    load_controller_config "$target"
    log="$ROOT_DIR/controllers/$target/logs/controller.log"

    # Remember how much evidence existed, so we can prove none was lost.
    pre_lines=$(log_mark "$log")

    docker stop --timeout "$CONTAINER_STOP_TIMEOUT_SECONDS" "$CONTROLLER_CONTAINER_NAME" >/dev/null
    rc=0
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p7down" 3 >/dev/null 2>&1 || rc=$?
    if [ "$rc" = "0" ]; then
        echo "FAIL: the $target route still answered while stopped." | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    $target stopped; its route is down (probe rc=$rc)." "$phase_log"

    mark=$(log_mark "$log")
    docker start "$CONTROLLER_CONTAINER_NAME" >/dev/null

    if ! wait_for_marker "$log" "$mark" \
        "$target START controller started; udp_port=$CONTROLLER_UDP_PORT" 60; then
        echo "FAIL: $target did not write its startup marker after restart." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! wait_for_marker "$log" "$mark" "LISTEN bound udp 0.0.0.0:$CONTROLLER_UDP_PORT" 60; then
        echo "FAIL: $target restarted but never rebound its port." | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    $target restarted and rebound udp/$CONTROLLER_UDP_PORT." "$phase_log"

    # The exchange must RESUME, evidenced by a fresh RX/TX pair after the mark.
    if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
        "$target" "$CONTROLLER_UDP_PORT" "p7rung2" 3 >/dev/null 2>&1; then
        echo "FAIL: the $target route did not resume after restart." | tee -a "$phase_log" >&2
        return 1
    fi
    if ! log_since "$log" "$mark" | grep -Fq 'RX ' || ! log_since "$log" "$mark" | grep -Fq 'TX '; then
        echo "FAIL: $target logged no fresh exchange after restart." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $target restarted, rebound, and its UDP exchange resumed." | tee -a "$phase_log"

    # The gate forbids losing independent log evidence across a recovery.
    if [ "$(log_mark "$log")" -le "$pre_lines" ]; then
        echo "FAIL: $target lost log evidence across the restart." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: $target's pre-fault log evidence survived the restart." | tee -a "$phase_log"

    for other in payload comms; do
        load_controller_config "$other"
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
            "$other" "$CONTROLLER_UDP_PORT" "p7rung2-$other" 3 >/dev/null 2>&1; then
            echo "FAIL: the $other route broke while $target was recovered." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: the other two routes were unaffected." | tee -a "$phase_log"
}

# RUNG 3 -- recover the whole OBC, leaving the controllers up.
verify_phase_7_rung3_obc() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local mark app ctrl image_before image_after hellos c started_before

    timeline "--- Rung 3: OBC restart ---" "$phase_log"

    # "Without manually rebuilding the image" is proven, not assumed.
    image_before=$(docker inspect -f '{{.Image}}' "$OBC_CONTAINER_NAME")
    started_before=""
    for c in "${CONTROLLERS[@]}"; do
        load_controller_config "$c"
        started_before="$started_before $(docker inspect -f '{{.State.StartedAt}}' "$CONTROLLER_CONTAINER_NAME")"
    done

    mark=$(log_mark "$console")
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    start_obc >/dev/null

    if ! wait_for_marker "$console" "$mark" 'CFE_ES_Main entering OPERATIONAL state' \
        "$OBC_STARTUP_TIMEOUT_SECONDS"; then
        echo "FAIL: cFE did not reach OPERATIONAL after the OBC restart." | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    cFE reached OPERATIONAL after the restart." "$phase_log"

    # All three apps must load EXACTLY once -- no duplicates, none missing.
    for app in "${ICARUS_APPS[@]}"; do
        local au
        au="$(printf '%s' "$app" | tr '[:lower:]' '[:upper:]')"
        if ! wait_for_marker "$console" "$mark" "$au: hello world from" 90; then
            echo "FAIL: $app did not come back after the OBC restart." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    hellos=$(log_since "$console" "$mark" | grep -c 'hello world from' || true)
    if [ "${hellos:-0}" != "3" ]; then
        echo "FAIL: expected exactly 3 app initialisations after restart, saw ${hellos:-0}." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: all three apps loaded exactly once; no duplicate registrations." | tee -a "$phase_log"

    # Schedule restored: every app back at its declared rate. A stale or lost
    # subscription would show up here as missing markers, so this is also the
    # "no stale subscriptions" evidence.
    for app in "${ICARUS_APPS[@]}"; do
        local needed=7 deadline
        deadline=$((SECONDS + PHASE5_COLLECT_TIMEOUT_SECONDS))
        while [ "$SECONDS" -lt "$deadline" ] \
            && [ "$(marker_count "$OBC_LOG_DIR/$app.log")" -lt "$needed" ]; do
            sleep 5
        done
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-rate-check \
            "/logs/$app.log" "$(app_declared_rate_mhz $app)" 5 5 >/dev/null 2>&1; then
            echo "FAIL: $app did not return to its declared rate after the OBC restart." \
                | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: the schedule was restored; all three rates are back in tolerance." | tee -a "$phase_log"

    for ctrl in "${CONTROLLERS[@]}"; do
        load_controller_config "$ctrl"
        if ! docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-udp-probe \
            "$ctrl" "$CONTROLLER_UDP_PORT" "p7rung3-$ctrl" 3 >/dev/null 2>&1; then
            echo "FAIL: the $ctrl transport path did not come back." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    echo "PASS: all three transport paths work again." | tee -a "$phase_log"

    # The controllers must not have been disturbed.
    local started_after=""
    for c in "${CONTROLLERS[@]}"; do
        load_controller_config "$c"
        started_after="$started_after $(docker inspect -f '{{.State.StartedAt}}' "$CONTROLLER_CONTAINER_NAME")"
        if [ "$(docker inspect -f '{{.RestartCount}}' "$CONTROLLER_CONTAINER_NAME")" != "0" ]; then
            echo "FAIL: controller $c restarted during the OBC recovery." | tee -a "$phase_log" >&2
            return 1
        fi
    done
    if [ "$started_before" != "$started_after" ]; then
        echo "FAIL: the controllers were restarted during the OBC recovery." | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: all three controllers stayed up untouched." | tee -a "$phase_log"

    image_after=$(docker inspect -f '{{.Image}}' "$OBC_CONTAINER_NAME")
    if [ "$image_before" != "$image_after" ]; then
        echo "FAIL: the OBC image changed; recovery must not require a rebuild." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: recovery used the existing image; no rebuild was needed." | tee -a "$phase_log"
}

# A recovery that cannot succeed must stay visibly degraded, never report normal.
verify_phase_7_failed_recovery() {
    local phase_log="$1"
    local console="$OBC_LOG_DIR/cfe-console.log"
    local app=adcs_sim app_upper=ADCS_SIM mark

    timeline "--- Failed recovery: must stay visibly degraded ---" "$phase_log"

    # Bring the OBC up with the app absent, so a restart of it cannot work.
    mark=$(log_mark "$console")
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    ICARUS_DISABLED_APPS="$app" start_obc >/dev/null
    if ! wait_for_marker "$console" "$mark" 'CFE_ES_Main entering OPERATIONAL state' \
        "$OBC_STARTUP_TIMEOUT_SECONDS"; then
        echo "FAIL: the OBC did not start for the failed-recovery test." | tee -a "$phase_log" >&2
        return 1
    fi

    mark=$(log_mark "$console")
    docker exec "$OBC_CONTAINER_NAME" /usr/local/bin/icarus-cfe-cmd \
        "$PHASE7_ES_CMD_MID" "$PHASE7_ES_RESTART_APP_CC" "$app_upper" >/dev/null 2>&1 || true

    # It must say something; a silent no-op would be the worst outcome.
    #
    # Bounded POLL, not a fixed sleep: the console is asynchronous, so the
    # refusal can surface tens of seconds after the command. A fixed 5s sleep
    # here reported "neither refused nor reported" against an ES that had in
    # fact refused correctly.
    if ! wait_for_marker "$console" "$mark" \
        "Restart Application $app_upper, GetAppIDByName failed" 90; then
        echo "FAIL: the impossible recovery was neither refused nor reported." \
            | tee -a "$phase_log" >&2
        log_since "$console" "$mark" | grep -iE "restart|ES_" | tail -3 | tee -a "$phase_log" >&2
        return 1
    fi

    # And it must NOT also claim success. A successful restart surfaces within
    # ~6s, so by the time the refusal is visible a success would be too.
    if log_since "$console" "$mark" | grep -Fq "Restart Application $app_upper Completed"; then
        echo "FAIL: ES reported a successful restart of an app that is not loaded." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    timeline "    ES refused the restart and said so." "$phase_log"

    # And the component must still be visibly degraded, not reported nominal.
    if log_since "$console" "$mark" | grep -Fq "$app_upper: hello world from"; then
        echo "FAIL: $app appears initialised after a recovery that could not succeed." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    if log_since "$console" "$mark" | grep -Fq "$app_upper: wakeup"; then
        echo "FAIL: $app is producing wakeups although it was never recovered." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: the failed recovery was refused, reported, and left $app visibly degraded." \
        | tee -a "$phase_log"

    # Restore a fully nominal system so the phase does not leave damage behind.
    mark=$(log_mark "$console")
    remove_container "$OBC_CONTAINER_NAME" >/dev/null
    start_obc >/dev/null
    if ! wait_for_marker "$console" "$mark" "$app_upper: hello world from" \
        "$OBC_STARTUP_TIMEOUT_SECONDS"; then
        echo "FAIL: could not restore a nominal system after the failed-recovery test." \
            | tee -a "$phase_log" >&2
        return 1
    fi
    echo "PASS: nominal operation restored at the end of the ladder." | tee -a "$phase_log"
    timeline "Phase 7 recovery ladder complete." "$phase_log"
}

phase_7() {
    stop
    clean_logs
    build
    build_controllers
    start
    verify_phase_7
}

main() {
    case "${1:-}" in
        build) build ;;
        build-controllers) build_controllers ;;
        start-obc) start_obc ;;
        start) start ;;
        stop) stop ;;
        status) status ;;
        logs) logs "${2:-obc}" ;;
        clean-logs) clean_logs ;;
        phase)
            case "${2:-}" in
                1) phase_1 ;;
                2) phase_2 ;;
                3) phase_3 ;;
                4) phase_4 ;;
                5) phase_5 ;;
                6) phase_6 ;;
                7) phase_7 ;;
                *) usage >&2; exit 2 ;;
            esac
            ;;
        -h|--help|help|'') usage ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
