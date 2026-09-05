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

## Prove the gate can fail

An assertion that cannot fail proves nothing. When a phase gate is added,
deliberately break each thing it claims to check and confirm it goes red, then
restore. For Phase 3 that meant: stopping a controller, probing a wrong port,
feeding the server malformed and oversized datagrams, and putting `udp.env` out
of step with a `runtime.env` — each produced the expected failure and exit code.
Record what was exercised in [status.md](status.md).
