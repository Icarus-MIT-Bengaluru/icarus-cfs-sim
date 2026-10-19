# The Seven-Phase Development Ladder

This is the authoritative phase plan. Development order is strict: **a phase
may not start until the preceding phase's gate passes.** Do not move
later-phase behavior into an earlier phase to make a demo work.

Current progress is tracked in [status.md](status.md).

| Phase | Establishes | Status |
|---|---|---|
| 1 | One cFS OBC reaches operational state | **Passed** |
| 2 | Four containers run independently on an isolated network | **Passed** |
| 3 | OBC can reach each controller over UDP | **Passed** |
| 4 | The three subsystems are separate cFS applications | **Passed** |
| 5 | SCH drives deterministic activity at declared rates | **Passed** |
| 6 | Faults are visible and contained | **Passed** |
| 7 | The recovery ladder restores nominal operation | **Passed** |

---

## Phase 1 — Single OBC baseline

**Goal:** Build a reproducible OBC image and prove one cFS instance reaches
operational state.
**cFS concepts:** cFE startup, ES lifecycle, OSAL, EVS.

**Implemented:** pinned cFS source, OBC Docker target, cFS launch entrypoint,
persistent console log, and the `run.sh phase 1` assertion.

**Gate:**

1. A fresh checkout initializes the pinned submodule and builds the image.
2. `run.sh start-obc` starts exactly one container named for the OBC.
3. cFE reaches operational state within the configured timeout — the exact
   marker is `CFE_ES_Main entering OPERATIONAL state`.
4. The host log directory holds timestamped startup evidence *after the
   container is stopped*.
5. `run.sh phase 1` passes only when that marker is present.

**Explicit non-goals:** no custom ICARUS apps, no UDP sockets, no scheduler
tables, no additional containers.

---

## Phase 2 — Container baseline

**Goal:** Bring up independently managed OBC, ADCS, Payload, and Comms
containers on a private network with independent log mounts.
**cFS concepts:** OSAL tasks, cFS runtime configuration, event/logging
boundaries.

**Implemented:** BusyBox controller target, per-controller runtime
configuration, the `icarus-net` bridge, lifecycle/status/log commands, and the
phase test.

**Gate:** all four containers remain running; the OBC is operational; every
controller writes its own startup marker to its own log; all four are attached
to `icarus-net`.

**Explicit non-goals:** UDP packets, custom cFS apps, scheduler behavior,
fault injection, recovery.

---

## Phase 3 — UDP transport proof

**Goal:** Prove the OBC-to-controller network paths *before* cFS component apps
are introduced.
**cFS concepts:** none yet — this phase is deliberately outside cFS.

**Implemented:** the shared static echo server, the OBC probe, `udp.env`, and
the `run.sh phase 3` gate. Details in
[peripherals.md](peripherals.md); results in [status.md](status.md).

**What was built:**

1. Replace the Phase 2 controller keepalive with one common UDP echo server in
   `controllers/`. Build it as a small static native binary in a build stage and
   keep BusyBox as the controller runtime. It must bind the controller's
   configured port, log receive/send events, return a deterministic
   acknowledgement, handle one request at a time, and reject malformed or
   oversized packets without exiting.
2. Add a project-owned OBC UDP probe utility to the OBC image. It is a
   temporary transport test tool — not a cFS app, not a flight component. It
   sends a fixed payload to one alias/port, waits with a bounded timeout for the
   acknowledgement, and returns nonzero on mismatch or timeout.
3. Extend `run.sh phase 3` to run the probe against `adcs:31001`,
   `payload:31002`, and `comms:31003`; append results to
   `controllers/obc/logs/udp-probe.log`; and inspect each controller log for the
   same message token and acknowledgement.
4. Add `controllers/obc/config/udp.env` as the single mapping source for
   aliases, ports, message tokens, and timeouts. Per-controller `runtime.env`
   files stay authoritative for each controller's own identity and port.

**Gate:** every route succeeds, with matching request/response tokens in both
the OBC probe log and the correct controller log. The gate additionally fails if
`udp.env` and any `runtime.env` disagree on a port, or if a token appears in
more than one controller's log.

**Boundary:** this proves Docker UDP transport only. Do not claim cFS Software
Bus routing here. Malformed-input *rejection* is implemented in this phase
because the server must not die on bad input; systematic fault **injection** is
Phase 6.

---

## Phase 4 — Separate cFS subsystem applications

**Goal:** Add independently built and configured placeholder cFS apps inside
the single OBC while preserving the three external controller boundaries.
**cFS concepts:** cFS app structure, SB subscriptions, tables/configuration,
EVS event design.

**Implement:**

1. Create `adcs_sim`, `payload_sim`, and `comms_sim` from the official cFS
   skeleton/sample-app structure in their matching `apps/` folders. Each gets
   its own headers, source, CMake integration, startup entry, command/telemetry
   definitions, event IDs, message IDs, configuration, and unit-test scaffold.
2. Add a project-owned mission overlay under `controllers/obc/config/mission/`.
   It registers the three app source directories, loads their shared objects at
   startup, and defines their IDs and configuration **without modifying
   `cfs/`** — see
   [cfs-notes.md](cfs-notes.md#mission-overlay-without-touching-the-submodule).
   This overlay is also where SBN and the unused stock apps get dropped.
3. Update the OBC Docker build to copy the project app sources and the overlay
   into the builder before `native_std.prep`.
4. Each app emits a distinct startup event and a periodic hello/heartbeat,
   publishes an app-owned SB message, writes its own persistent log under
   `controllers/obc/logs/`, and owns only its matching UDP adapter.
5. Enforce the separation rules in
   [architecture.md](architecture.md#binding-constraints) item 4.
6. Extend `run.sh phase 4` to verify app registration and startup, three
   distinct app logs, unique event/message IDs, and isolation — by deliberately
   disabling one app and confirming the other two continue.

**Status: gate passed 2026-10-17** with 13/13 assertions, including the
isolation proof. The app **function bodies remain deliberate skeletons** — the
gate proves integration and isolation, not subsystem behaviour. That is the
agreed scope, not an outstanding defect.

**Decisions taken before implementation (2026-10-17, by the user):**

1. **Per-app logs are produced at the boundary, not by the app.** Each app emits
   only EVS events, staying idiomatic cFS; the OBC entrypoint parses the console
   stream and routes lines to `adcs_sim.log`, `payload_sim.log`, and
   `comms_sim.log` by app name. This satisfies the
   [logging contract](testing.md#logging-contract) without putting filesystem
   access in an app. Accepted trade-off: the three files come from one filtered
   stream rather than three independent writers, so "separate logs" is a property
   of the splitter, not of the apps — Phase 6 evidence must not overclaim here.
2. **The overlay keeps a minimal stock app set:** `sch_lab` (required by Phase 5),
   `hs` (required by Phase 6), and `ci_lab` + `to_lab` (a command/telemetry path
   for interactive debugging). **SBN and the other ten** (`cf`, `ds`, `fm`, `lc`,
   `sc`, `md`, `mm`, `cs`, `hk`, `sample_app`) are dropped.

**Defaults I will apply unless told otherwise:** three non-overlapping topic-ID
blocks per cFS convention via each app's `*_topicid_values.h`; the Phase 3
`udp-probe` stays in the image as a transport-only regression tool; and the
Phase 4 heartbeat runs on a simple self-driven wakeup, with SCH taking over the
timing in Phase 5 (not earlier).

**Gate:** all three apps load separately; each produces its own hello evidence
and touches only its designated controller route; stopping one does not stop
unrelated apps or controller containers.

**What `run.sh phase 4` checks today** (6 assertions, all passing): the Phase 3
gate re-verified; each app loaded from its own `.so`; each emitted its startup
hello; none exited; each has its own non-empty log containing no other app's
events; each greeted only its own controller; and the topic-ID and event-ID
blocks are unique across all three.

**The isolation proof** restarts the OBC with `adcs_sim` dropped from the
startup script (via `ICARUS_DISABLED_APPS`, a test affordance in the OBC
entrypoint — no rebuild needed) and requires: cFE still reaches OPERATIONAL;
the disabled app is neither loaded nor heartbeating; its controller route goes
quiet and no other app takes it over; both surviving apps stay loaded, keep
heartbeating, and keep their own routes; and all three return when re-enabled.

---

## Phase 5 — Scheduler and timing proof

**Goal:** Move periodic placeholder work under cFS SCH control.
**cFS concepts:** SCH, TIME, software-bus scheduling, housekeeping-ready
telemetry.

**Implement:**

1. Add a project-owned SCH table to the mission overlay. Do not alter the cFS
   sample table in the submodule.
2. Drive the phase test with scheduled SB wakeup messages rather than
   free-running app loops. Assign documented rates of **10 Hz, 1 Hz, and
   0.1 Hz** to the three placeholder activities and record the mapping in the
   mission config.
3. Include a sequence number and a monotonic timestamp in each app's scheduled
   log marker. Add an OBC-hosted checker, invoked by `run.sh phase 5`, that
   computes interval samples and reports rate/jitter failures.
4. Keep app logs separate; retain the validation report in
   `controllers/obc/logs/phase-5-verification.log`.

**Status: gate passed 2026-10-17** with 6/6 assertions.

**Rate assignment** (authoritative copy is the schedule table):

| App | Rate | `PacketRate` | Measured |
|---|---|---|---|
| `adcs_sim` | 10 Hz | 1 (100 ms) | 9.9950 Hz, jitter 89.5–116.8 ms |
| `payload_sim` | 1 Hz | 10 (1.0 s) | 0.9995 Hz, jitter 992.8–1019.9 ms |
| `comms_sim` | 0.1 Hz | 100 (10.0 s) | 0.1000 Hz, jitter 9997.5–10012.1 ms |

**Declared tolerance:** mean interval within **±5%** of nominal, and no single
interval above **2× nominal**. Sequence numbers must be contiguous, which is
what catches missing and duplicate wakeups. There is deliberately **no
minimum-interval assertion**: `sch_lab` hands ticks over a counting semaphore,
so queued ticks are consumed back-to-back after a stall and a short interval is
legitimate catch-up, not a fault.

**Gate:** all three activities appear at their declared rates for the full test
window within that tolerance. Missing, duplicate, or late wakeups fail the
phase.

---

## Phase 6 — Fault observation and containment

**Goal:** Demonstrate that a fault is detected, logged, and limited to its
affected component wherever possible.
**cFS concepts:** HS monitoring, EVS diagnostics, watchdog boundaries, fault
containment.

**Implement:**

1. Enable and configure cFS Health and Safety monitoring for the placeholder
   apps. Define expected heartbeat/execution-counter behavior and record HS
   events in the OBC logs. Note the container limitation in
   [cfs-notes.md](cfs-notes.md#hs-system-monitor-fails-in-a-container).
2. Add simulation-only, clearly labeled fault hooks — **not flight behavior** —
   for: app heartbeat stall, app controlled exit, controller stop, controller
   UDP disconnect, malformed/oversized UDP input, and unavailable log mount.
3. Make `run.sh phase 6` inject each fault independently with bounded waits,
   capturing the affected app/controller/OBC logs plus an aggregate report.
4. Required containment: for a stopped controller, unaffected OBC apps and the
   other two paths continue. For malformed UDP input, the target controller logs
   the rejection and stays alive. For app faults, HS emits detection evidence.
   Malformed input never terminates cFE or another app.

**Status: gate passed 2026-10-18** with 17/17 assertions across six faults.

| # | Fault | Injection | Detection |
|---|---|---|---|
| 1 | App stall (alive, not working) | `INJECT_STALL` via ci_lab | HS EID 41 `App Monitor Failure ... Action: Event Only` |
| 2 | App controlled exit | `CFE_ES_STOP_APP` via ci_lab | `CFE_ES_ExitApp` + HS name-not-found |
| 3 | Controller stopped | `docker stop` | probe exit 5, `resolve-failed` |
| 4 | Controller unreachable | `docker network disconnect` | probe nonzero, container still alive |
| 5 | Malformed/oversize UDP | bad datagrams | all four `REJECT` reasons, `restarts=0` |
| 6 | Unavailable log mount | read-only `/logs` on a controller **and** the OBC | warning emitted, process keeps running |

Every fault also asserts containment: unrelated apps keep their rates, and
unrelated controller routes keep answering.

**Explicitly OUT of scope — not demonstrable in this container.** The
`linux_sysmon` PSP module cannot read `/proc/schedstat`, so `HS_AppInit`
returns early and two things never initialise: **CPU-utilisation/hogging
detection** and **HS watchdog arming** (`CFE_PSP_WatchdogSet/Service/Enable`).
Application monitoring is unaffected and is what this gate uses. The
"watchdog boundaries" concept in this phase's cFS-concepts list is therefore
**documented as not demonstrable rather than claimed**. See
[cfs-notes.md](cfs-notes.md#hs-system-monitor-fails-in-a-container).

**Gate:** every injected fault has a traceable source and a detection event;
unrelated paths stay live; no fault silently disappears.

---

## Phase 7 — Recovery ladder

**Goal:** Restore nominal placeholder operation progressively, proving both
entry into degraded operation and return to nominal service.
**cFS concepts:** ES restart behavior, HS recovery hooks, safe restart
sequencing, recovery verification.

**Implement:**

1. Document the recovery order in the mission config and the test report:
   **app recovery → controller restart → OBC restart.**
2. For app recovery, use cFS Executive Services dynamic-app lifecycle/restart
   semantics rather than restarting the whole OBC when only one app failed.
   Verify one active instance and that it resumes only its own heartbeat.
3. For controller recovery, restart the named container, wait for its startup
   marker, then require the matching app's UDP exchange to resume.
4. For OBC recovery, restart only `icarus-obc` and require cFE operational
   state, all three apps loaded exactly once, the schedule restored, and all
   three transport paths working. Controller containers stay up.
5. Add `run.sh phase 7` with bounded checks and a full recovery timeline in
   `controllers/obc/logs/phase-7-verification.log`.

**Status: gate passed 2026-10-19** with 16/16 assertions.

| Rung | Scope | Mechanism | Proven |
|---|---|---|---|
| 1 | One app | `CFE_ES_RESTART_APP` by ground command | A **hard-stalled** app (blocked in `OS_TaskDelay`) is recovered: restarted once, re-initialised, state reset (`wakeup seq=1`), back at its declared rate, own route working, other two apps untouched, HS re-armed |
| 2 | One controller | `docker start` | Restarted, rebound its port, UDP exchange resumed, **pre-fault log evidence preserved**, other two routes unaffected |
| 3 | The OBC | container restart | cFE OPERATIONAL, all three apps loaded **exactly once**, schedule restored (all three rates re-measured), all three transport paths back, controllers untouched, **image unchanged** |
| — | Failed recovery | restart an app that is not loaded | Refused, reported (`GetAppIDByName failed`), and left visibly degraded — never reported normal |

**Recovery order is documented in the mission config**, as this phase requires:
[`controllers/obc/config/mission/README.md`](../controllers/obc/config/mission/README.md).

**Gate:** each rung returns its component to the declared nominal state without
duplicate app registrations, stale subscriptions, or loss of independent log
evidence — and **without manually rebuilding the image**. A recovery failure
must leave the component in a visible degraded/safe placeholder state rather
than falsely reporting normal.

---

## Project complete

All seven gates pass, last re-run in sequence on **2026-10-19** followed by a
68-assertion sweep of one live stack and 21/21 on evidence persistence; see the
[validation record](status.md#full-ladder-re-verification--2026-10-19-utc).
Against the completion criteria in
[architecture.md](architecture.md#completion-criteria): one OBC cFS instance
runs three isolated placeholder apps; each has a verified UDP path to its own
independently managed simulator; all logs are separated and persistent;
scheduled activity is validated against declared rates; and failures can be
observed, isolated, and recovered.

**What remains deliberately out of scope**, and is documented rather than
claimed: the app function bodies are skeletons (no ADCS control, payload
processing or radio protocol), and CPU-hog detection and HS watchdog arming are
unavailable in this container. See [status.md](status.md).
