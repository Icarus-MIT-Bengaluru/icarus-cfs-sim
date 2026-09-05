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
                *) usage >&2; exit 2 ;;
            esac
            ;;
        -h|--help|help|'') usage ;;
        *) usage >&2; exit 2 ;;
    esac
}

main "$@"
