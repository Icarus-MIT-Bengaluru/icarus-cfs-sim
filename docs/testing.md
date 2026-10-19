# Testing and Evidence

## Test method

- Every phase gate is a `./run.sh phase <1-7>` command.
- Each phase command starts from clean containers and fresh timestamped logs,
  builds the image targets it needs, runs **bounded** assertions, injects only
  that phase's defined faults, and returns pass/fail.
- A later phase may depend on earlier gates but **must not silently skip them.**
  A later phase invokes or re-verifies the relevant earlier gate. (`phase 2`
  already re-runs the Phase 1 operational-state check.)
- **A phase may not be started until the preceding phase passes.**
- Phase evidence stays in the existing controller log directories; the aggregate
  summary for each phase goes in `controllers/obc/logs/`.

## Assertion style

- **Prefer named marker assertions over arbitrary sleeps.** Sleeps are allowed
  only as small polling intervals, and every wait must have a deadline.
- Exit nonzero on any failed assertion.
- Clean only known ICARUS runtime state — never unrelated containers, networks,
  or images.

## Logging contract

| Producer | Required persistent evidence |
|---|---|
| OBC / cFE | `controllers/obc/logs/cfe-console.log`, extracted `cfe-evs.log` |
| Phase checks | `controllers/obc/logs/phase-N-verification.log` |
| UDP probe (Phase 3+) | `controllers/obc/logs/udp-probe.log` |
| ADCS simulator | `controllers/adcs/logs/controller.log` |
| Payload simulator | `controllers/payload/logs/controller.log` |
| Comms simulator | `controllers/comms/logs/controller.log` |
| Custom cFS apps (Phase 4+) | One dedicated OBC log per app: `adcs_sim.log`, `payload_sim.log`, `comms_sim.log` |

The three per-app logs are produced by an awk splitter in the OBC entrypoint,
which routes each EVS line to a file by originating app name. The apps
themselves only emit EVS events. This satisfies the contract, but the
separation is a property of the splitter rather than of three independent
writers — Phase 6 evidence must not overclaim it. See
[peripherals.md](peripherals.md) and
[status.md](status.md#resolved-source-conflicts).

Every log line carries a UTC timestamp, the component's identity, an event
type, and a test message token or sequence value where applicable.

**Never send all output to one undifferentiated log file.** Separated logs are
the mechanism by which fault isolation is proven in Phase 6; collapsing them
destroys the evidence the project exists to produce.

Logs are host-mounted so that removing a container never loses boot evidence.
Generated files are Git-ignored except `.gitkeep`.

> cFE's own EVS lines carry mission-elapsed time rather than UTC — see
> [cfs-notes.md](cfs-notes.md#cfe-event-time-is-not-wall-clock-time).

## Static checks

Keep these lightweight and runnable without a live daemon:

```sh
bash -n run.sh
sh -n controllers/obc/config/entrypoint.sh
sh -n controllers/controller-entrypoint.sh
git diff --check
```

From Phase 4, add C/CMake compilation, cFS app unit tests, and log-parser tests
to the static set.

## Runtime acceptance

Runtime acceptance is Docker-based. **Start a daemon before claiming success,
and never report a phase as passed on static checks alone.**

Verifying a gate means checking the evidence, not just the exit code:

1. The gate command exits zero.
2. The expected marker is present in the expected log.
3. The evidence files exist, are non-empty, and **still exist after
   `./run.sh stop`.**
4. Container and network state match what the gate claims.

If a gate cannot be made to pass, report the exact failing assertion and its log
evidence rather than declaring the phase green.

## Counting evidence

Three things in this project look like counters and are not. Each produced a
false failure during the 2026-10-19 sweep.

**A `phase-N-verification.log` accumulates; it is not one run's tally.** Later
gates re-run earlier verifiers, and those append to the same file, so the
Phase 6 file held 20 PASS lines for a 17-assertion gate and carried two run
headers. A gate's own assertion count is what it prints on **stdout**. Assert
at-least against the file, never equality.

**A cumulative log cannot answer a per-boot question.** `cfe-console.log` spans
every boot, so grepping it for `OPERATIONAL` after a restart matches history and
"succeeds" instantly. Read per-boot facts from that container's own
`docker logs`, or latch a marker and count only what follows it.

**An image ID changes on every build, even when nothing rebuilds.** BuildKit
exports a fresh attestation/provenance manifest each time and provenance embeds
timestamps, so the manifest-list digest `docker images --quiet` prints differs
run to run with every step `CACHED`. Prove an image is current by its
**content** — `exe/cpu1/cf/` should hold 9 `.so` files and
`cfe_es_startup.scr` 8 entries — not by comparing IDs.

And one path fact that has caught this project twice: cFS stages modules,
tables and the startup script in `exe/cpu1/`**`cf/`**, not `exe/cpu1/`. A check
pointed at the parent directory finds nothing and, if it is an absence check,
passes for the wrong reason.

## Timing evidence

**Never measure timing from when a log line appeared.** OSAL's console is
asynchronous, so lines are delivered in bursts — see
[cfs-notes.md](cfs-notes.md#console-output-is-asynchronous). Any component whose
rate or latency is being checked must embed a monotonic timestamp in its own
message, and the checker must do arithmetic only on those embedded values.
File order, file mtime, and `docker logs` arrival times are all unusable for
this purpose.

For the same reason, a test that waits for log output must wait for a **sample
count** with a generous deadline, not for a wall-clock duration.

## Fault injection catalogue (Phase 6)

| Fault | How it is injected | Gotcha |
|---|---|---|
| App stall | `icarus-cfe-cmd` → app `INJECT_STALL` | must stop the app re-entering `CFE_ES_RunLoop`, or the execution counter keeps advancing and HS detects nothing |
| App exit | `icarus-cfe-cmd` → `CFE_ES_STOP_APP` (MID `0x1806`, fcncode **5**) | — |
| Controller stop | `docker stop` | presents as `resolve-failed`, not a timeout |
| Controller unreachable | `docker network disconnect` | container must stay alive; distinct signature from a stop |
| Malformed/oversize UDP | datagrams to the controller port | implemented in Phase 3; Phase 6 asserts it |
| Unavailable log mount | `--mount type=tmpfs,destination=/logs,readonly` | **omitting the mount injects nothing** (the image creates `/logs`), and `tmpfs-mode=0555` injects nothing either (root bypasses permission bits). Only the `readonly` flag blocks the write |

Two measurement traps worth remembering:

- **Latch evidence as it appears, not after the wait.** When file logging is
  unavailable the 10 Hz app floods container stdout and Docker's log rotation
  discards the early lines, so re-reading `docker logs` at the end of a wait can
  find neither the warning nor the `OPERATIONAL` line that were definitely
  printed.
- **A single missed wakeup at 10 Hz is below this host's noise floor.** 0.13% of
  intervals legitimately exceed 2× nominal from scheduler jitter, and a lone
  dropped tick is indistinguishable from that by interval alone. The rate gate
  therefore detects systematic rate error, sustained lateness, and gross stalls
  — it does **not** claim to detect one isolated missed tick.

## Verifying a recovery

A recovery assertion is only real if it would notice a recovery that silently
did nothing. Four rules, each learned from a mechanism that reports success too
early or too loosely:

1. **Break it first.** Recovering a healthy component proves nothing. Inject the
   fault and confirm the degraded state is observable before recovering.
2. **Never trust the recovery mechanism's own success message.** ES reports a
   restart `Completed` as soon as the task is spawned, before the app's `Init`
   has run. Assert the component's *own* startup evidence as well.
3. **Assert the fault is gone, not that output resumed.** For a scheduled app
   that means re-measuring its declared rate, not seeing a marker appear.
4. **Prove state was actually reset.** A restarted ICARUS app resumes at
   `wakeup seq=1`; if the sequence continues from where it left off, the
   "restart" was a no-op.

And test a recovery that **cannot** succeed: it must be refused, reported, and
leave the component visibly degraded. A recovery check that only ever sees
success can quietly be a no-op.

## Prove the gate can fail

An assertion that cannot fail proves nothing. When a phase gate is added,
deliberately break each thing it claims to check and confirm it goes red, then
restore. For Phase 3 that meant: stopping a controller, probing a wrong port,
feeding the server malformed and oversized datagrams, and putting `udp.env` out
of step with a `runtime.env` — each produced the expected failure and exit code.
Record what was exercised in [status.md](status.md).
