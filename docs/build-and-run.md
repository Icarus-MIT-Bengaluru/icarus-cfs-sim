# Build and Run

## Host prerequisites

- A running Docker daemon. Runtime acceptance is Docker-based; **start a daemon
  before claiming any phase passes.**
- Git, for the pinned submodule.
- **macOS cannot build cFS's `native_std` target directly** — it has no Linux
  PSP. Build and execute through Docker. `run.sh` itself runs on the host, so it
  stays portable between GNU and BSD userlands.

Validated on: Docker Desktop 29.7.2, server `linux/arm64`, 8 CPUs, 8 GB.

## First-time setup

```sh
git submodule update --init --recursive
```

This initializes the cFS bundle and its nested submodules at their pinned
commits. See [cfs-notes.md](cfs-notes.md#the-pinned-bundle).

## Image build

The `Dockerfile` has four stages:

| Stage | Base | Purpose |
|---|---|---|
| `tools` | `debian:bookworm-slim` | Compiles the two project-owned C utilities with `-Wall -Wextra -Werror`. Kept separate from the cFS build so controller-only builds stay fast |
| `controller` | `busybox:1.36.1-musl` | The device-simulator image: the entrypoint plus the static echo server. No dependency on the cFS build |
| `builder` | `debian:bookworm-slim` | Installs the toolchain; copies `cfs/`, the project `apps/`, and the mission overlay; runs `make native_std.prep && make native_std.install` |
| `obc` | `debian:bookworm-slim` | Lean runtime. Copies the staged `exe/cpu1/` tree from `builder`, the OBC entrypoint, and the UDP probe |

**Linking is not uniform, on purpose.** The echo server is built `-static`
because the BusyBox controller runtime has no libc; it needs no name resolution,
so static costs it nothing. The probe is dynamically linked because it must
resolve container aliases through glibc's resolver, which a static glibc binary
cannot do. See [peripherals.md](peripherals.md#components).

cFS is built from the checked-in submodule rather than downloaded during the
build, so the produced binary is repeatable.

**The mission overlay is assembled in the builder, never on the host.**
`sample_defs` is copied to `icarus_defs`, the files in
`controllers/obc/config/mission/` are layered on top, and the build selects it
with `-DMISSIONCONFIG=icarus` passed through a command-line
`PREP_OPTS_native_std` assignment. Project app sources live at
`/opt/icarus/apps` and are found via `CFS_APP_PATH`, which accepts absolute
paths — so nothing is ever written into `cfs/`.

**A green build is not sufficient evidence.** A build has been observed to exit
0 while producing an image with a stale startup script and missing modules.
Confirm what landed: `cfe_es_startup.scr` and the staged `.so` set in
`/opt/icarus/cfs/exe/cpu1/cf/`. `run.sh phase 4` asserts both.

The OBC entrypoint starts `core-cpu1` from its staged directory and records the
full console stream to `/logs/cfe-console.log` using `stdbuf` and `tee`, which
preserves line-oriented output in the host-mounted log directory.

## Command surface

`run.sh` is the only supported interface. Every command is listed here.

```sh
./run.sh build              # Build the pinned cFS OBC image
./run.sh build-controllers  # Build the lightweight controller image
./run.sh start-obc          # Start only the OBC on the private network
./run.sh start              # Start the OBC and all three controllers
./run.sh stop               # Stop/remove ICARUS containers and the network
./run.sh status             # Show every ICARUS container state
./run.sh logs [obc|adcs|payload|comms]   # Tail a component's persistent log
./run.sh clean-logs         # Remove generated logs, keeping .gitkeep
./run.sh phase 1            # Build, start, and verify the Phase 1 gate
./run.sh phase 2            # Build, start, and verify the Phase 2 gate
./run.sh phase 3            # Build, start, and verify the Phase 3 UDP gate
./run.sh phase 4            # Build, start, and check app integration
```

`stop` is destructive **only** to the named ICARUS containers and the exact
`icarus-net` network; it leaves unrelated containers alone. It sends SIGTERM
first (`docker stop --timeout 5`) so each component runs its signal handler and
records a clean shutdown, then removes the container. `clean-logs`
removes generated files from the four known log folders but preserves
`.gitkeep`.

## What a phase command does

`phase N` runs `stop` → `clean-logs` → build the required image targets →
start the required containers → run bounded assertions. It exits nonzero on any
failed assertion. See [testing.md](testing.md).

## Runtime configuration

`run.sh` sources the `runtime.env` files. They are **non-secret configuration
only — never add credentials.**

| File | Keys |
|---|---|
| `controllers/obc/config/runtime.env` | `OBC_CONTAINER_NAME`, `OBC_IMAGE`, `OBC_STARTUP_TIMEOUT_SECONDS` (45), `CFS_VERSION`, `ICARUS_NETWORK_NAME` |
| `controllers/<name>/config/runtime.env` | `CONTROLLER_NAME`, `CONTROLLER_CONTAINER_NAME`, `CONTROLLER_IMAGE`, `CONTROLLER_UDP_PORT` |
| `controllers/obc/config/udp.env` | The OBC-side endpoint map — see [peripherals.md](peripherals.md#endpoint-map) |

**Images are tagged by role, not by phase** (`icarus-cfs-obc:dev`,
`icarus-controller:dev`). A phase-numbered tag goes stale the moment the next
phase lands, which is exactly what happened to the original `:phase1` /
`:phase2` tags once Phase 3 added binaries to both images.

## Container launch details

- The OBC launches with `--sysctl fs.mqueue.msg_max=64`, which the cFS native
  Linux target requires for POSIX message queues. Without it cFE fails during
  startup.
- Every container attaches to `icarus-net` with a network alias (`obc`, `adcs`,
  `payload`, `comms`) and bind-mounts its own host log directory at `/logs`.
- The bridge is created with `--internal`; no controller port is published to
  the host.
