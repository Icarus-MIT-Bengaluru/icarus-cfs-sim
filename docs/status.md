# Status and Change Log

## Current state

| Phase | Status | Evidence |
|---|---|---|
| 1 — OBC baseline | **Runtime-passed 2026-09-05** | `phase-1-verification.log` |
| 2 — Container baseline | **Runtime-passed 2026-09-05** | `phase-2-verification.log` |
| 3 — UDP transport | **Runtime-passed 2026-09-05** | `phase-3-verification.log`, `udp-probe.log` |
| 4 — cFS apps | Not started | — |
| 5 — Scheduler | Not started | — |
| 6 — Fault containment | Not started | — |
| 7 — Recovery | Not started | — |

Implemented in the working tree: the `tools`, `controller`, `builder`, and `obc`
Docker targets; both entrypoints; the shared UDP echo server and the OBC probe;
four `runtime.env` files plus `udp.env`; and the `run.sh` lifecycle with the
Phase 1, 2, and 3 verifiers.

**Git state:** the repository was newly initialized during this work.
`.gitmodules` and the `cfs` gitlink are staged; project files remain untracked.
Nothing has been committed. Do not use destructive Git commands or discard the
uncommitted work.

## Runtime validation record — 2026-09-05 (UTC)

Environment: Docker Desktop 29.7.2, server `linux/arm64`, 8 CPUs, 8 GB.

| Gate | Command | Result | Wall clock |
|---|---|---|---|
| Phase 1 | `./run.sh phase 1` | exit 0 — `PASS: cFE entered OPERATIONAL state.` | 2m25s incl. full cFS build |
| Phase 2 | `./run.sh phase 2` | exit 0 — 5/5 PASS assertions | 10s (cFS image layer cached) |

Verified beyond the exit codes:

- `CFE_ES_Main entering OPERATIONAL state` present in `cfe-console.log`.
- All three controllers wrote their own startup marker with the correct
  reserved port (31001 / 31002 / 31003) to their own log.
- `./run.sh status` showed four containers up; `icarus-net` confirmed
  `internal=true` with exactly the four expected members.
- All seven required evidence files survived `./run.sh stop` with content
  intact.
- `bash -n` and both `sh -n` checks plus `git diff --check` pass.

This supersedes the earlier "no Docker daemon available" blocker, under which
Phases 1 and 2 had only ever passed static checks.

## Phase 3 validation record — 2026-09-05 (UTC)

`./run.sh phase 3` exits 0 with 6/6 PASS assertions: the Phase 2 gate
re-verified, the `udp.env` map agreeing with every `runtime.env`, and all three
round trips confirmed on both ends. Measured round-trip time was under 1 ms on
every route.

Evidence: `controllers/obc/logs/udp-probe.log` and
`phase-3-verification.log`, plus `RX`/`TX` pairs carrying the matching token in
each `controllers/<name>/logs/controller.log`.

**The gate was negative-tested** — each thing it claims to check was
deliberately broken and confirmed to go red:

| Injected fault | Observed |
|---|---|
| Malformed payload (`bad-prefix`) | Rejected, server alive |
| 900-byte datagram (`oversize`, limit 512) | Rejected, server alive |
| Non-printable bytes | Rejected, server alive |
| Empty token (`bad-token`) | Rejected, server alive |
| Valid probe after the malformed barrage | Still exits 0 — no corruption of state |
| Stopped controller | Probe exit 5, `reason=resolve-failed` |
| Wrong port on a live controller | Probe exit 3, `reason=timeout` |
| `udp.env` port out of step with `runtime.env` | Gate exits 1 with the mismatch named |

After each negative test the controller container showed `restarts=0`,
confirming the server rejects bad input rather than dying and being restarted.

Phases 1 and 2 were re-run afterwards and still pass, so the Phase 3 changes did
not regress the earlier gates.

## Integration verification — 2026-09-05 (UTC)

Phases 1-3 were verified as a **system**, not only as individual gates:

- **Cold sequence.** With all ICARUS images, containers, and logs removed, the
  gates were run in order 1 -> 2 -> 3. All three exited 0 (1/1, 5/5, 6/6 PASS).
- **Simultaneous state.** With the stack up after Phase 3, 16/16 assertions held
  at once: four containers running with zero restarts, `icarus-net` internal
  with exactly four members, `core-cpu1` alive with cFE OPERATIONAL, all three
  controller START markers in separate files, and a live round trip on every
  route.
- **Isolation.** No route's token appears in any other controller's log (all 6
  cross-pairs checked), and a probe token lands in exactly one log.
- **Gate layering.** The Phase 3 report contains the Phase 2 re-verification and
  the Phase 1 OPERATIONAL evidence, so later gates re-prove earlier ones rather
  than assuming them.
- **Idempotency.** `phase 3` run twice back to back: 6/6 both times.
- **Out-of-order use.** Running `phase 1` after `phase 3` tears the controllers
  down (by design — Phase 1 is an OBC-only gate) and re-running `phase 3`
  restores the full stack.
- **Persistence.** All nine evidence artifacts survive `./run.sh stop` non-empty.

**Defect found and fixed during this verification:** `run.sh stop` removed
containers with `docker rm --force`, which sends SIGKILL. Every component's
SIGTERM handler was therefore skipped and no shutdown evidence was ever
recorded — the controllers' `STOP` line simply never appeared. `remove_container`
now issues `docker stop --timeout 5` before removal, and all three controllers
log `STOP controller stopping` on teardown. This mattered beyond tidiness:
Phase 6 needs to distinguish a clean stop from a crash, and Phase 7 restarts
controllers and the OBC deliberately.

## Open items

1. **SBN starts in the OBC today** — inherited cFS vendor default. Drop it in
   the Phase 4 mission overlay. See
   [cfs-notes.md](cfs-notes.md#sbn-loads-by-default).
2. **HS system monitor fails at boot** in the container. Not a Phase 1/2 gate
   failure, but Phase 6 depends on HS. See
   [cfs-notes.md](cfs-notes.md#hs-system-monitor-fails-in-a-container).
3. **cFE event time is mission-elapsed, not UTC**, while the logging contract
   asks for UTC. Blocks nothing yet; matters for Phase 5 rate checking. See
   [cfs-notes.md](cfs-notes.md#cfe-event-time-is-not-wall-clock-time).
4. **A stopped controller surfaces as `resolve-failed`, not a timeout**, because
   Docker's embedded DNS withdraws the alias when the container stops. Phase 6
   and Phase 7 must expect that shape. See
   [peripherals.md](peripherals.md#behavior-worth-knowing).
5. **cFE logs no shutdown line of its own.** Controllers now log a clean `STOP`,
   but the OBC console just ends. Phase 7 needs a positive marker that the OBC
   went down deliberately rather than died, so the OBC entrypoint likely needs a
   shutdown log line of its own.
6. **Two latent `run.sh` fragilities** found by reading, not yet triggered:
   `verify_phase_1 | tee` under `set -e -o pipefail` aborts `phase 2` before it
   can write a FAIL summary; and `container_on_icarus_network` matches the whole
   formatted network line, so it would break if a container ever joined a second
   network. Neither has fired; fix when touched.

## Resolved source conflicts

These documents consolidate three overlapping design briefs and the former
the former root `AGENT_HANDOFF.md`. Where they disagreed:

| Conflict | Resolution |
|---|---|
| One brief listed six phases with Phase 7's recovery gate dangling under Phase 6 | The **seven-phase ladder** is authoritative — [phases.md](phases.md) |
| One brief had Phase 1 loading all three placeholder apps with hello telemetry | Wrong; Phase 1 is a bare cFE baseline. Apps arrive in **Phase 4** |
| One brief described a single shared Debian image for OBC and simulators | As-built is a **BusyBox** controller image, independent of the cFS toolchain — [build-and-run.md](build-and-run.md#image-build) |
| One brief named `start-all` / `stop-all` commands | Actual commands are **`start`** and **`stop`** — [build-and-run.md](build-and-run.md#command-surface) |
| Mission config placed at `controllers/obc/config/` vs `.../config/mission/` | The overlay lives in **`controllers/obc/config/mission/`** |
| A brief's Phase 1 tree omitted files that exist | Tree corrected to as-built — [repository-layout.md](repository-layout.md#tree-as-built) |
| One brief's "Test Method" section was empty | Filled from the seven-phase brief — [testing.md](testing.md) |
| Phase 6 fault list differed between briefs | Merged; the union is listed, including the unavailable-log-mount fault |

## Change log

### 2026-09-05 — Integration verification of Phases 1-3

Verified the three phases compose, not just pass individually — see the
integration record above. Fixed `run.sh stop` to terminate containers
gracefully (`docker stop` before `docker rm`) so signal handlers run and
shutdown evidence is preserved.

### 2026-09-05 — Phase 3 implemented and runtime-passed

Added the shared UDP device-simulator echo server
(`controllers/udp-echo-server.c`, static, one datagram at a time, four
rejection paths), the OBC transport probe
(`controllers/obc/tools/udp-probe.c`, dynamically linked for alias
resolution), the OBC-side endpoint map (`controllers/obc/config/udp.env`),
a `tools` Docker stage compiling both under `-Wall -Wextra -Werror`, and
`run.sh phase 3`. See the validation record above.

Two consequential changes fell out of this work:

- **The controller entrypoint now execs the echo server** instead of idling, so
  its startup marker changed from `Phase 2 controller <name> started; UDP port
  reserved: <port>` to `<name> START controller started; udp_port=<port>`. The
  Phase 2 verifier was updated to match, and Phase 2 re-run to prove it.
- **Images are now tagged by role, not phase** (`icarus-cfs-obc:dev`,
  `icarus-controller:dev`). The old `:phase1`/`:phase2` tags became inaccurate
  the moment Phase 3 added binaries to both images.

### 2026-09-05 — Documentation restructure
Split the monolithic `AGENT_HANDOFF.md` into this `docs/` set by topic, folded
in the three design briefs, removed duplicated statements, and resolved the
conflicts tabulated above. All 55 distinct facts from the old handoff were
audited into the new set before it was removed; its unique content — the
non-negotiable rules and the first-actions sequence — became root `CLAUDE.md`,
which Claude Code loads automatically at session start. `AGENT_HANDOFF.md` is
gone; `README.md` and `CLAUDE.md` are the entry points.

### 2026-09-05 — Phases 1 and 2 runtime-validated
Executed both gates against a live daemon for the first time; both passed. See
the validation record above.

**Defect found and fixed:** `run.sh logs` used GNU-only
`tail --follow --lines=100`, which BSD `tail` on the macOS host rejects, so the
command failed for every component. Changed to `tail -f -n 100`, accepted by
both GNU and BSD, and verified against the live ADCS log. This was the only
change required — the `Dockerfile` and both entrypoints ran unmodified.

### Earlier — Phases 1 and 2 implemented
Built the pinned submodule wiring, both Docker targets, both entrypoints, the
runtime configuration files, and the `run.sh` lifecycle and verifiers. Static
checks passed; no runtime verification was possible at the time.
