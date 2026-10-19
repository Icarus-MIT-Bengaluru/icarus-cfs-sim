# Status and Change Log

## Current state

| Phase | Status | Evidence |
|---|---|---|
| 1 — OBC baseline | **Runtime-passed**, re-verified 2026-10-17 | `phase-1-verification.log` |
| 2 — Container baseline | **Runtime-passed**, re-verified 2026-10-17 | `phase-2-verification.log` |
| 3 — UDP transport | **Runtime-passed**, re-verified 2026-10-17 | `phase-3-verification.log`, `udp-probe.log` |
| 4 — cFS apps | **Runtime-passed 2026-10-17** | `phase-4-verification.log`, `adcs_sim.log` + 2 |
| 5 — Scheduler | **Runtime-passed 2026-10-17** | `phase-5-verification.log` |
| 6 — Fault containment | **Runtime-passed 2026-10-18** | `phase-6-verification.log` |
| 7 — Recovery | **Runtime-passed 2026-10-19** | `phase-7-verification.log` |

Implemented in the working tree: the `tools`, `controller`, `builder`, and `obc`
Docker targets; both entrypoints; the shared UDP echo server, the OBC probe and
the ground-command sender; the three app skeletons and the mission overlay that
registers them; the OBC-hosted rate checker; four `runtime.env` files plus
`udp.env`; and the `run.sh` lifecycle with all seven phase verifiers.

**Git state:** two commits exist on `main` (`25d3cbb` initial, `47ae87c` the
skeleton through Phase 3), and that is also all the `origin` remote holds.
Phases 4-7 -- 42 changed or untracked paths -- are **uncommitted**. Do not use
destructive Git commands or discard the uncommitted work.

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

## Phase 4 skeleton integration — 2026-10-17 (UTC)

`./run.sh phase 4` exits 0 with 6/6 PASS. **This is not a Phase 4 pass**: the
app bodies are stubs and the gate's isolation requirement is unimplemented. See
[phases.md](phases.md#phase-4--separate-cfs-subsystem-applications).

What now works, verified on the live stack:

- Three separate cFS apps (`adcs_sim`, `payload_sim`, `comms_sim`), 31 files
  each, built from the vendor `sample_app` skeleton with real cFS structure:
  EVS registration, an SB command pipe with CMD and SEND_HK subscriptions, a
  housekeeping telemetry message, a command-dispatch switch, and a private UDP
  adapter. Function bodies are intentionally minimal.
- Each emits `hello world from <subsystem>` at startup and a self-driven
  heartbeat every 5s. **The heartbeat is not SCH-driven — that is Phase 5.**
- Each sends exactly one UDP hello to its own controller at init, and all three
  are confirmed received and acknowledged in the controllers' own logs.
- The mission overlay drops **SBN** and ten unused stock apps: the startup
  script went from 17 entries to 8, and the staged module set from 20 `.so` to
  9. Retained: `sch_lab`, `hs`, `ci_lab`, `to_lab`, `cfe_assert`.
- Per-app logs are produced by an awk splitter in the OBC entrypoint. Verified
  isolated: `adcs_sim.log` holds 6 ADCS_SIM events and 0 from other apps.
- The unit-test harness is wired; `coverage-<app>-app-testrunner` is staged and
  the placeholder test runs 3/3 PASS.

**Both ID assertions were negative-tested:** duplicating a topic ID across two
apps and duplicating an event-ID base each made the gate exit 1 with the
specific conflict named.

Phases 1-3 were re-run afterwards and still pass (1/1, 5/5, 6/6).

### Defects found and fixed during this work

1. **`payload_sim` could not create its SB pipe** and exited, while the other
   two started fine. `OS_QueueCreate returned -13` is `OS_ERR_NAME_TOO_LONG`:
   `OSAL_CONFIG_MAX_API_NAME` is 20, and `"PAYLOAD_SIM_CMD_PIPE"` is exactly 20
   characters, so with the null terminator it overflowed. The other two names
   were shorter and passed. Pipe names are now `<APP>_PIPE` (≤16 chars) and
   pipe depth was reduced 32→8, which also leaves POSIX mqueue headroom.
2. **Missing `mission_build.cmake` per app.** `arch_build.cmake` declares only
   the platform-scope generated headers; the mission-scope set
   (`*_topicid_values.h` and friends) needs its own file, without which the
   `to_lab`/`sch_lab` table builds fail on a missing header.
3. **Unit-test harness linked against a stubs library that did not exist.**
   `add_cfe_coverage_dependency` expects `add_cfe_coverage_stubs`; the fix was
   to compile all of an app's units into one test object via `SUBJECT_SOURCES`.
4. **A false failure in my own Phase 4 assertion.** The event-ID check compared
   `printf '%s'` output against `sort -u` output, which appends a trailing
   newline, so the counts never matched and a correct repo reported a conflict.

### A build result that could not be trusted

The first `./run.sh build` after adding the apps **exited 0 while producing an
image with the pre-change startup script and no ICARUS modules.** Building the
`builder` stage explicitly surfaced three real errors that the `obc` target had
reported as success. Treat a green build as evidence only alongside an
inspection of what landed in the image: check `cfe_es_startup.scr` and the
staged `.so` set, which is what `run.sh phase 4` now asserts.

## Phases 1-4 integration test — 2026-10-17 (UTC)

Verified the four phases compose, from a cold start with no containers, no
ICARUS images and no logs. All four gates passed in sequence (1/1, 5/5, 6/6,
6/6) and **65/65** integration assertions passed:

| Group | Checked |
|---|---|
| Phase 1 properties | cFE OPERATIONAL, `core-cpu1` alive, exactly one OBC |
| Phase 2 properties | 4 containers, 0 restarts, `icarus-net` internal with 4 members, 3 separate START markers |
| Phase 3 properties | 3 ports bound, 3 live probe round trips, probe log complete |
| Phase 4 properties | 3 apps loaded from own `.so`, 3 hello-world events, none exited, 3 separate logs, SBN absent, startup script exactly 8 entries |
| Isolation | all 6 app↔controller cross-pairs clean; 3 per-app logs with 0 foreign events |
| Gate chain | phase 4 → phase 3 → phase 2 traceable; every phase log independently records OPERATIONAL |
| Persistence | all 13 artifacts survive `./run.sh stop`; 3 graceful `STOP` lines |

One assertion initially failed and was **my test's error, not a defect**: it
expected `phase-4-verification.log` to transitively contain the literal
Phase 1 OPERATIONAL line. It does not, by design — each phase log owns its own
summary and names the predecessor gate it re-proved, so the chain is
`phase 4 → "Phase 3 gate re-verified" → phase-3 log → OPERATIONAL`. Corrected
to assert the chain rather than transitive containment.

## Phase 4 gate closed — 2026-10-17 (UTC)

`./run.sh phase 4` now exits 0 with **13/13 PASS**, including the isolation
requirement that was the last outstanding item. Phase 4 is passed and Phase 5
is unblocked.

The isolation proof restarts the OBC with one app disabled and verifies that
cFE still reaches OPERATIONAL, the disabled app is absent and silent, its
controller route is quiet with no other app taking it over, both surviving apps
keep running and keep their own routes, and all three return on re-enable.
It was negative-tested: breaking the disable mechanism made the gate exit 1
with `adcs_sim was still loaded despite being disabled`.

**App function bodies remain deliberate skeletons.** The gate proves
integration and isolation, not subsystem behaviour — the agreed scope.

### CORRECTION: the startup latency was log buffering, not VM slowness

The entry below originally attributed the 19/25/47s startup variance to
"host-side Docker Desktop VM and bind-mount latency". **That was wrong.** The
real cause is OSAL's asynchronous console: `OSAL_CONFIG_CONSOLE_ASYNC` defaults
`TRUE`, so `OS_printf` queues into a ring that a separate task drains, and
output arrives in bursts. cFE boots in well under a second; the OPERATIONAL
line simply sat in a buffer.

Proof: three heartbeat events whose own cFE timestamps were 5.4-6.3s apart all
arrived at the container's stdout within 0.4ms of each other, followed by 84s
of silence. The gap is in delivery, not execution.

Raising `OBC_STARTUP_TIMEOUT_SECONDS` to 120 remains the correct mitigation —
the line genuinely is not visible for that long — but the stated reason has
been fixed in `runtime.env`, `CLAUDE.md` and `docs/cfs-notes.md`.

### Defect found: the startup timeout was too tight for this environment

`OBC_STARTUP_TIMEOUT_SECONDS` was 45. Identical OBC restarts were measured
reaching OPERATIONAL in **19s, 25s and 47s** — so the budget was already
marginal and would have made *any* phase flaky, not just Phase 4.

cFE is not the cause: its own clock shows a sub-second boot, and the 44s
wall-clock gap sits between two consecutive container stdout lines immediately
before `CFE_ES_StartApplications`. DNS was ruled out (alias resolution measured
at 1-4ms), and so was the log splitter (the gap is visible in `docker logs`,
upstream of it). The residual cause is host-side Docker Desktop VM and
bind-mount latency on macOS. The timeout is now **120s**.

## Phase 5 passed — 2026-10-17 (UTC)

`./run.sh phase 5` exits 0 with 6/6 PASS in ~196s. Periodic activity is now
driven by `sch_lab` wakeup messages; the self-driven `CFE_SB_ReceiveBuffer`
timeout has been removed from all three apps, which now pend forever and act
only on their scheduled wakeup.

| App | Declared | Measured | Error | Jitter (min/max) | Samples |
|---|---|---|---|---|---|
| `adcs_sim` | 10 Hz | 9.9950 Hz | −0.05% | 89.5 / 116.8 ms | 1206 |
| `payload_sim` | 1 Hz | 0.9995 Hz | −0.05% | 992.8 / 1019.9 ms | 118 |
| `comms_sim` | 0.1 Hz | 0.1000 Hz | 0.00% | 9997.5 / 10012.1 ms | 10 |

Declared tolerance: mean within ±5%, no interval above 2× nominal, contiguous
sequence numbers. All three rates came in within 0.05% of nominal, confirming
the drift-free `CLOCK_MONOTONIC` timebase.

**Negative-tested:** changing `payload_sim`'s `PacketRate` from 10 to 20 made
the gate exit 1, reporting 0.4999 Hz against a declared 1 Hz (+100.05% interval
error). The checker's five assertions were additionally unit-tested against
synthetic logs covering a skipped sequence number, an over-long interval, a
systematic rate error, a realistic stall-plus-catch-up, and a multi-boot log.

Gates 1-5 were all re-run afterwards and pass (1/1, 5/5, 6/6, 13/13, 6/6).

### Design decisions worth knowing

- **Timing is measured from a monotonic timestamp the app embeds in each
  marker**, never from log arrival — console output is delivered in bursts.
  `CFE_PSP_GetTime` + `OS_TimeGetTotalMicroseconds` gives one `int64` that
  cannot tear. `CFE_TIME_GetMET()` was tried first and rejected: its subseconds
  were observed wrapping without the seconds field carrying, producing negative
  intervals.
- **No minimum-interval assertion.** `sch_lab` uses a counting semaphore, so
  queued ticks are consumed back-to-back after a stall; a short interval is
  legitimate catch-up.
- **The checker segments on sequence resets**, because the per-app log outlives
  the container and Phase 4's isolation check restarts the OBC twice. Only the
  most recent run is measured — intervals must never span a reboot.
- **Exactly one EVS event per wakeup.** EVS allows 15/sec per app and 10 Hz
  uses 10; the gate asserts no squelching occurred.

### Defects found and fixed during this work

1. **Phase 4's isolation check broke** when the marker text changed from
   `heartbeat` to `wakeup` — its liveness probe stopped matching. Found by
   running the gates, fixed, and Phase 4 is back to 13/13.
2. **`grep -c` prints `0` and exits 1** when there are no matches, so a
   `|| echo 0` fallback emitted `0\n0` and broke a numeric comparison.
3. **The collection loop counted every marker in the file**, including previous
   boots, so it finished early and left the 0.1 Hz app short of samples. It now
   reads the last marker's sequence number, which is the current run's count.
4. **awk comments are `#`, not `/* */`** — the latter parsed as a regex and the
   checker would not run at all.

## Phases 1-5 integration verification — 2026-10-17 (UTC)

Verified all five phases compose, from a cold start with no containers, no
ICARUS images and no logs.

Gates in sequence, all green: **1/1, 5/5, 6/6, 13/13, 6/6** (9s, 12s, 14s, 41s,
198s).

**65/65** integration assertions on one live stack:

| Group | Checked |
|---|---|
| Phase 1 | cFE OPERATIONAL, `core-cpu1` alive, exactly one OBC |
| Phase 2 | 4 containers, 0 restarts, `icarus-net` internal with 4 members, 3 separate START markers |
| Phase 3 | 3 ports bound, 3 live probe round trips |
| Phase 4 | 3 apps from own `.so`, 3 hello-worlds, none exited, 3 separate logs, SBN absent, startup script exactly 8 entries |
| Phase 5 | 3 apps emitting scheduled wakeups with monotonic timestamps, all 3 rates re-measured live and within tolerance, no EVS squelching, self-driven heartbeat gone from the code, 3 wakeup MIDs in the schedule table |
| Isolation | all 6 app↔controller cross-pairs clean; 3 per-app logs with 0 foreign events |
| Gate chain | each phase log names its immediate predecessor, 5→4→3→2→1; all 5 independently record OPERATIONAL |
| Persistence | all 14 artifacts survive `./run.sh stop`; 3 graceful `STOP` lines |

Unit tests: 3/3 PASS in each of the three apps. Static checks and the markdown
link check all pass.

One assertion initially failed and was **the test's error, not a defect** — the
same mistake made during the Phase 1-4 verification. It expected
`phase-5-verification.log` to transitively contain the Phase 2 result. It does
not, by design: each phase log records its own summary and names only the
predecessor gate it re-proved, so the chain is followed link by link rather than
being flattened into the newest log. Corrected to assert each link.

## Phase 6 passed — 2026-10-18 (UTC)

`./run.sh phase 6` exits 0 with **17/17** assertions across six independently
injected faults, each with a traceable source, a detection event, and a
containment check on unrelated components. Report in
`phase-6-verification.log`.

New capability:

- `controllers/obc/config/mission/tables/hs_amt.c` — HS application monitoring
  for the three apps, `HS_AMTActType_EVENT` (report, do not act).
- `controllers/obc/tools/cfe-cmd.c` — sends real CCSDS ground commands to
  ci_lab's UDP port (1234). Used here for `CFE_ES_STOP_APP`; Phase 7 reuses it
  for `CFE_ES_RESTART_APP`.
- A simulation-only `INJECT_STALL` command in each app, clearly labelled.
- The OBC entrypoint now degrades gracefully when `/logs` is unwritable.
- `HS_WAKEUP_MID` added to the schedule table, pinning the HS cycle to 1.0 s so
  the detection window is exactly `CycleCount × 1.0 s` = ~20 s.

**Negative-tested, three ways:** disabling an app's AMT entry (`NOACT`) failed
the gate at the precondition check (`good = 2`, not 3); a lowercase AMT name
produced `App Monitor App Name not found` at runtime despite validating as
"good"; and breaking the stall hook so the app only *acknowledged* the command
failed the gate at HS detection — proving that assertion is not a tautology.

Gates 1-6 all re-run afterwards and pass (1/1, 5/5, 6/6, 13/13, 6/6, 17/17).

### Out of scope, explicitly

The `linux_sysmon` failure means **CPU-hog detection and HS watchdog arming
never initialise**. Application monitoring is unaffected. Phase 6 documents
both as not demonstrable in this container rather than claiming them — see
[cfs-notes.md](cfs-notes.md#hs-system-monitor-fails-in-a-container).

### The Phase 5 jitter rule changed

Phase 6's heavier container churn tripped Phase 5's per-interval cap:
`adcs_sim` hit 221.4 ms against the 200 ms (2×) limit. Measured distribution
over 1527 samples: mean 100.6 ms (+0.6%), **2 intervals (0.13%) above 2×, none
above 3×**. Asserting on the absolute maximum across ~1500 samples is fragile —
one scheduler hiccup fails an otherwise healthy run.

The rule is now **99th percentile within 2× nominal, plus a hard 5× ceiling**
(user-selected). The percentile catches sustained lateness; the ceiling catches
a genuinely dropped or stalled wakeup. Verified: the real log that failed the
old rule gives p99 = 115.1 ms and passes, while a synthetic 6× stall still
fails.

### Defects found and fixed during this work

1. **The stall hook was initially useless.** It returned early from the wakeup
   handler, but `CFE_ES_RunLoop` keeps incrementing the execution counter — the
   very thing HS watches — so HS would never have detected it. The stall now
   blocks inside the loop body so the counter freezes.
2. **`CFE_ES_STOP_APP` is function code 5, not 4.**
3. **Omitting the `/logs` mount injects no fault** — the image creates the
   directory. Nor does `tmpfs-mode=0555`, because root bypasses permission bits.
   Only `readonly` works.
4. **A shell redirection failure is not suppressed by the command's
   `2>/dev/null`**, so the OBC writability probe printed an error and exited
   before its own test could run. Uses `touch` now.
5. **Docker log rotation discarded the evidence** the log-mount assertion was
   re-reading after its wait. Evidence is now latched as it appears.

## Phase 7 passed — 2026-10-19 (UTC)

`./run.sh phase 7` exits 0 with **16/16** assertions and a timestamped recovery
timeline in `phase-7-verification.log`. **All seven gates now pass**, so the
project meets its completion criteria.

| Rung | Result |
|---|---|
| 1 — app recovery | 4/4. A **hard-stalled** app is fully recovered by `CFE_ES_RESTART_APP` |
| 2 — controller restart | 3/3, including preservation of pre-fault log evidence |
| 3 — OBC restart | 5/5, including exactly-once app loading and an unchanged image |
| Failed recovery | 2/2. Refused, reported, left visibly degraded |

New capability: `run.sh phase 7`, a `wait_for_nominal` baseline guard, and the
recovery order documented in the mission config.

### What the ES investigation established

- **A hard-blocked task is recoverable.** ES does not wait for cooperation — it
  force-cancels via `pthread_cancel`, and `OS_TaskDelay`'s `clock_nanosleep` is
  a cancellation point. This matters because a hard stall is the only stall HS
  can detect, so the fault HS reports is the fault app-scope recovery fixes.
- **The restart is deferred ~5 s** (`APP_KILL_TIMEOUT × APP_SCAN_RATE`), so
  short timeouts flake against healthy restarts.
- **`Completed` does not mean the app is up** — it fires when the task is
  spawned, before `Init` runs. The gate therefore also asserts the app's own
  startup event, `wakeup seq=1` (proof state was reset), and its declared rate.
- **A commanded processor reset would kill the OBC permanently** in this PSP, so
  rung 3 is a container restart and `HS_AMTActType_PROC_RESET` must never be
  used. Recorded in the mission config.
- **HS monitors are one-shot**; recovery is incomplete until re-armed with
  DISABLE-then-ENABLE. `ENABLE` alone logs `*already* Enabled` and refreshes
  nothing — a failed re-arm that looks like success.

### Defects found and fixed during this work

1. **The failed-recovery rung used a fixed `sleep`** and reported "neither
   refused nor reported" against an ES that had refused correctly — the refusal
   arrived later through the async console. Now a bounded poll. This is exactly
   the trap documented in [testing.md](testing.md#timing-evidence), walked into
   anyway.
2. **The ladder started before the stack was nominal.** Phase 6 ends by
   restarting the OBC, so rung 1 injected its fault into a still-booting cFE and
   the command was dropped — the rung failed for the wrong reason. A
   `wait_for_nominal` guard now establishes the baseline first.
3. **Assertion text was wrong.** The observable "initiated" line is the ES
   SysLog form without a trailing period; the EVS DEBUG event that has one is
   filtered by the default event-type mask.

### A note on how these assertions were validated

The Phase 7 gate **failed twice during development for genuine reasons** (both
above) before passing, which is direct evidence the assertions discriminate
rather than rubber-stamp. Dedicated negative tests were attempted but proved
unreliable: run by sourcing `run.sh` into zsh rather than through its own bash
shebang, they left the stack degraded and then failed at setup rather than at
the assertion under test. Those runs are **not** counted as evidence.

## Open items

Reviewed and re-checked against the code on 2026-10-19.

1. **HS system monitor fails at boot** in the container. The `linux_sysmon` PSP
   module cannot read `/proc/schedstat`, so `HS_AppInit` returns early. This
   does **not** block application monitoring, which Phase 6 and Phase 7 depend
   on and which works; it does mean CPU-hog detection and watchdog arming are
   unavailable, and both are explicitly out of scope and never claimed. See
   [cfs-notes.md](cfs-notes.md#hs-system-monitor-fails-in-a-container).
2. **Two latent `run.sh` fragilities** found by reading, not yet triggered:
   `verify_phase_1 | tee` under `set -e -o pipefail` aborts `phase 2` before it
   can write a FAIL summary; and `container_on_icarus_network` matches the whole
   formatted network line, so it would break if a container ever joined a second
   network. Neither has fired in any gate run; fix when next touching them.
3. **No `LICENSE` file**, while the repository is public. A declaration is the
   owner's call; `README.md` states the absence rather than implying a licence.
4. **`controllers/obc/config/mission/tables/hs_amt.c` has mangled comment
   alignment** from an earlier scripted edit (`/*   1 */` on its own line). It
   compiles and the table validates; cosmetic only.

### Closed since the last review

| Was open | Resolution |
|---|---|
| SBN starts in the OBC | Dropped by the Phase 4 mission overlay; `exe/cpu1/cf/` contains no SBN module, and `phase 4` asserts it |
| cFE event time is mission-elapsed, not UTC | Superseded: every rate-bearing marker now embeds its own `mono_us` from `CFE_PSP_GetTime`, so no check depends on event time. The cFE behaviour itself is unchanged and documented in [cfs-notes.md](cfs-notes.md#cfe-event-time-is-not-wall-clock-time) |
| A stopped controller surfaces as `resolve-failed` | Still true as behaviour, no longer an action: Phases 6 and 7 expect that shape (`probe rc=5`) |
| cFE logs no shutdown line of its own | Fixed: the OBC entrypoint traps `INT TERM` and writes `OBC container stopping cFS native_std` to the console log before exiting |

## Full ladder re-verification — 2026-10-19 (UTC)

All seven gates re-run in sequence after a reset (containers and network
removed, `clean-logs`), then one live stack swept for every phase's properties
at once. Environment: Docker Desktop 29.8.2, server `linux/arm64`.

| Gate | Result | Time |
|---|---|---|
| `./run.sh phase 1` | exit 0, 1/1 | 9s |
| `./run.sh phase 2` | exit 0, 5/5 | 13s |
| `./run.sh phase 3` | exit 0, 6/6 | 14s |
| `./run.sh phase 4` | exit 0, 13/13 | 73s |
| `./run.sh phase 5` | exit 0, 6/6 | 197s |
| `./run.sh phase 6` | exit 0, 17/17 | 282s |
| `./run.sh phase 7` | exit 0, 16/16 | 428s |

Integration sweep on the live stack: **68/68**. Groups: Phase 1 baseline (3),
container mesh (6), three live UDP round trips confirmed on both ends (6), app
integration plus image content (12), scheduler rates re-measured live and
monotonicity (6), fault containment (4), recovery ladder (8), cross-app
ownership isolation (9), gate chain link by link (13).

Rates re-measured on the live stack, each the last segment of its log:

| App | Measured | Declared | Error | Samples | p99 |
|---|---|---|---|---|---|
| `adcs_sim` | 9.9918 Hz | 10.0000 Hz | +0.08% | 718 | 102.2ms |
| `payload_sim` | 0.9991 Hz | 1.0000 Hz | +0.09% | 69 | 1019.3ms |
| `comms_sim` | 0.0999 Hz | 0.1000 Hz | +0.10% | 5 | 10000.9ms |

Evidence persistence after `./run.sh stop`: **21/21** — all 16 artifacts
non-empty, a graceful `STOP` from each controller, no container or network left
behind. Unit tests 3/3 PASS, 0 FAIL in each of the three apps. Static checks
clean: `bash -n run.sh`, `sh -n` on both entrypoints and `rate-check.sh`,
`git diff --check`, and 15 markdown files with no broken links or anchors. The
stack was left running and confirmed operational.

### Five sweep failures, all of them test defects

Worth recording because each one looked like a product defect first:

1. **`.so` count 0 and startup entries empty** — the sweep looked in
   `exe/cpu1/`. Modules and `cfe_es_startup.scr` stage in `exe/cpu1/cf/`.
   Correct content confirmed there: 9 `.so`, 8 entries, no SBN. The
   "SBN is absent" check had been passing against the wrong directory too, so
   it was only genuinely proven after the fix.
2. **Phase 6 log showed 20 PASS for a 17-assertion gate**, Phase 7 33 for 16.
   A `phase-N-verification.log` **accumulates**: later gates re-run earlier
   verifiers, which append to the same file (the Phase 6 file carried two run
   headers). Assert at-least against the file; the gate's own count is what it
   prints on stdout.
3. **"phase 2 re-proved phase 1's gate" failed** — `phase-2-verification.log`
   does not contain a "Phase 1 gate re-verified" line. It re-runs phase 1's
   verifier and embeds its assertion verbatim
   (`PASS: cFE entered OPERATIONAL state.`). The chain is proven; the grep was
   looking for the wrong string at that one link.

Two further measurement traps, neither a product defect:

- **The OBC image ID changed across the ladder with all 32 build steps
  `CACHED`.** BuildKit exports a fresh attestation/provenance manifest on every
  export and provenance embeds timestamps, so the manifest-list digest that
  `docker images --quiet` prints differs run to run even when content is
  byte-identical. A before/after image-ID comparison is therefore **not** a
  valid staleness check; the content assertions are.
- **A restarted OBC "reached OPERATIONAL in 0s"** because the grep matched the
  eight occurrences already in the appended console log. Per-boot facts must be
  read from that container's own `docker logs`, not the cumulative file.

## Resolved source conflicts

These documents consolidate three overlapping design briefs and the former
root `AGENT_HANDOFF.md`. Where they disagreed:

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

### 2026-10-19 — Full ladder re-verified; docs reconciled

Re-ran all seven gates in sequence from a reset and swept one live stack 68/68,
plus 21/21 on evidence persistence. No code changed. Corrected the stale
working-tree and Git-state notes, rewrote the open-items list against the actual
code (four entries had been resolved by later phases), and recorded two
measurement traps: verification logs accumulate across nested gate runs, and the
image ID changes on every export even when nothing rebuilds.

### 2026-10-19 — Phase 7 passed; all seven gates green

Added the recovery ladder: app recovery through the real ES ground command,
controller restart, OBC restart, and a failed-recovery case that must stay
visibly degraded. Documented the recovery order in the mission config. Three
defects found and fixed; see the record above.

### 2026-10-18 — Phase 6 passed

Added HS application monitoring, a real cFE ground-command path, a
simulation-only stall hook, OBC log-mount hardening, and `run.sh phase 6` with
six independently injected faults. Changed the Phase 5 jitter rule to a 99th
percentile plus a 5x ceiling after the absolute-max rule proved fragile at
10 Hz. Five defects found and fixed; see the record above.

### 2026-10-17 — Phases 1-5 integration verified

Cold-start verification of all five phases together: gates green in sequence
and 65/65 integration assertions. No code changed.

### 2026-10-17 — Phase 5 passed

Moved periodic activity under SCH control: per-app wakeup command MIDs, three
schedule-table entries at 10/1/0.1 Hz, an OBC-hosted rate checker, and
`run.sh phase 5`. Corrected the earlier misattribution of startup latency.
Four defects found and fixed; see the record above.

### 2026-10-17 — Phase 4 gate closed

Added the isolation proof to `run.sh phase 4` (13/13 PASS) plus the
`ICARUS_DISABLED_APPS` test affordance in the OBC entrypoint, and raised
`OBC_STARTUP_TIMEOUT_SECONDS` from 45 to 120 after measuring 47s restarts.
Phase 4 is passed; Phase 5 is unblocked.

### 2026-10-17 — Phases 1-4 integration tested

Verified all four phases together from cold; 65/65 assertions. Recorded the
verified baseline in root `CLAUDE.md` so the next session sees it without
re-deriving it. No code changed.

### 2026-10-17 — Phase 4 app skeletons integrated

Added the three ICARUS cFS applications as skeletons with real structure and
stub bodies, the mission overlay that registers them and drops SBN, the per-app
log splitter, the unit-test harness, and `run.sh phase 4`. Four defects found
and fixed; see the integration record above. Phase 4 is deliberately **not**
marked passed.

### 2026-10-17 — Phases 1-3 re-verified

Re-ran all three gates on a cold machine (Docker Desktop stopped, no containers,
~6 weeks after the original run). All pass unchanged: phase 1 exit 0 (1/1), phase
2 exit 0 (5/5), phase 3 exit 0 (6/6). A 17-assertion integration sweep on the
live stack passed 17/17, 9/9 evidence artifacts survived `./run.sh stop`, all
three controllers logged a graceful `STOP`, and the static checks still pass. No
code changed.

**One infrastructure flake worth knowing:** the first `phase 1` attempt, launched
11 seconds after Docker Desktop started, died mid-build with
`failed to receive status: rpc error: code = Unavailable desc = error reading
from server: EOF`. That is buildkit dropping the connection while the daemon is
still settling, not a project defect — the same build succeeded moments later and
the retry passed in 12s. Give Docker Desktop a moment to settle before the first
build, and re-run rather than debug if you see that exact error.

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
