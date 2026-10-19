# ICARUS — Working Rules

This repository builds a **containerized cFS development/simulation skeleton**
for a 1U CubeSat. It is not flight software and must not be presented as a
flight-ready image.

Full documentation: **[`docs/`](docs/README.md)**. Read
[docs/status.md](docs/status.md) before doing anything — it says which phase is
current and what is still open.

## Verified baseline

Last full integration test: **2026-10-19**. All seven gates were run in
sequence from a reset (containers and network removed, logs cleaned), then a
single live stack was swept for every phase's properties at once.

| Gate | Result | Time |
|---|---|---|
| `./run.sh phase 1` | exit 0, 1/1 PASS | 9s |
| `./run.sh phase 2` | exit 0, 5/5 PASS | 13s |
| `./run.sh phase 3` | exit 0, 6/6 PASS | 14s |
| `./run.sh phase 4` | exit 0, 13/13 PASS | 73s |
| `./run.sh phase 5` | exit 0, 6/6 PASS | 197s |
| `./run.sh phase 6` | exit 0, 17/17 PASS | 282s |
| `./run.sh phase 7` | exit 0, 16/16 PASS | 428s |

**68/68** integration assertions passed on one live stack: every phase's
properties simultaneously true, three live UDP round trips, all three SCH rates
re-measured live (9.9918 / 0.9991 / 0.0999 Hz), app-to-controller ownership
isolated across all six cross-pairs, per-app logs free of foreign events, and
the gate chain traceable link by link (7→6→5→4→3→2→1). A further
**21/21** confirmed all 16 evidence artifacts surviving `./run.sh stop`, a
graceful `STOP` from every controller, and no container or network left behind.
Unit tests 3/3 in each app.

Two counting traps this verification hit, both worth knowing before trusting a
number:

- **A `phase-N-verification.log` accumulates.** Later gates re-run earlier
  verifiers, which append to the same file, so the file held 20 PASS lines for
  a 17-assertion gate. The gate's own count is what it prints on stdout; assert
  at-least against the file, never equality.
- **The OBC image ID changes on every build even when nothing was rebuilt.**
  BuildKit exports a fresh attestation/provenance manifest each time and
  provenance embeds timestamps, so the manifest-list digest differs run to run
  with all 32 steps `CACHED`. Image staleness must be judged by content (8
  startup entries, 9 staged `.so` in `exe/cpu1/cf/`), not by ID.

**All seven gates pass. The phase ladder is complete** — the project meets the
completion criteria in `docs/architecture.md`. There is no Phase 8; further work
is filling in the app bodies or extending scope, which needs the user's say.

The app function bodies are deliberate skeletons — the gates prove integration,
isolation, scheduling, fault containment and recovery, not subsystem behaviour,
which is the agreed scope.

**Not demonstrable in this container, and not claimed:** CPU-hog detection and
HS watchdog arming. The `linux_sysmon` PSP module cannot read
`/proc/schedstat`, so `HS_AppInit` returns early and both are skipped.
Application monitoring is unaffected. See `docs/cfs-notes.md`.

Two things worth knowing before you trust a build here:

- **A green build is not sufficient evidence.** A `./run.sh build` has been
  observed to exit 0 while producing an image with a stale startup script and
  no ICARUS modules. Confirm what landed in the image —
  `cfe_es_startup.scr` should have 8 entries and the staged `.so` set 9 files.
  `./run.sh phase 4` asserts both.
- **Give Docker Desktop a moment to settle.** A build started seconds after the
  daemon launches can die with `rpc error: code = Unavailable ... EOF`. That is
  buildkit, not this project; re-run rather than debug it.
- **Poll for log evidence; never sleep a fixed time and check once.** Because
  the console is asynchronous, a refusal or marker can surface tens of seconds
  after the action. A fixed 5s sleep made a Phase 7 assertion report failure
  against a perfectly correct cFE. Use `wait_for_marker`.
- **Start fault tests from a known-nominal stack.** A phase that ends by
  restarting the OBC leaves the next one injecting into a booting cFE, where
  commands are silently dropped. `wait_for_nominal` exists for this.
- **Log output is delivered in bursts, so never infer timing from it.** OSAL's
  console is asynchronous by default, so `OS_printf` output is queued and
  flushed in chunks: events 5-6s apart have arrived within 0.4ms of each other,
  followed by 84s of silence. Anything timing-related must embed its own
  timestamp in the message (see `docs/cfs-notes.md`). This is also why
  `OBC_STARTUP_TIMEOUT_SECONDS` is 120 — do not lower it — and why log-polling
  waits need generous deadlines.

## Non-negotiable rules

1. **Placeholder behavior only.** Do not implement ADCS control, payload logic,
   radio protocols, EPS, hardware drivers, or mission algorithms unless the user
   explicitly expands scope.
2. **Strict phase order, 1 through 7.** Do not move later-phase behavior into an
   earlier phase to make a demo work. A phase may not start until the preceding
   phase's gate passes.
3. **Never edit `cfs/`.** It is an unmodified vendor submodule pinned at v7.0.1.
   Integrate through a project-owned mission overlay and Docker build inputs.
4. **`run.sh` is the only orchestration interface.** Extend it; never add a
   competing one (no `docker-compose`).
5. **Never report a phase as passed on static checks alone.** Runtime acceptance
   requires a live Docker daemon, a zero exit code, and the evidence on disk —
   verified after `./run.sh stop`, not just during the run.
6. **Update `docs/` in the same change as the code**, and add a dated entry to
   the [change log](docs/status.md#change-log).
7. **Preserve the uncommitted work.** No destructive Git commands. Two commits
   exist on `main` (the skeleton through Phase 3), and that is all `origin`
   holds; Phases 4-7 are uncommitted in the working tree.

## Where things are

| If you need | Read |
|---|---|
| What is being built and why | [docs/architecture.md](docs/architecture.md) |
| Where things live and what you may change | [docs/repository-layout.md](docs/repository-layout.md) |
| Current phase and what comes next | [docs/phases.md](docs/phases.md) |
| Build, run, and command surface | [docs/build-and-run.md](docs/build-and-run.md) |
| cFS framework specifics and gotchas | [docs/cfs-notes.md](docs/cfs-notes.md) |
| The UDP device-simulator interface | [docs/peripherals.md](docs/peripherals.md) |
| Evidence and logging requirements | [docs/testing.md](docs/testing.md) |
| Current state, validation record, change log | [docs/status.md](docs/status.md) |

## First actions

1. Read [docs/README.md](docs/README.md) and [docs/status.md](docs/status.md).
2. Check `git status`; preserve all existing uncommitted files.
3. Confirm the baseline is still green before changing anything:

   ```sh
   git submodule update --init --recursive
   ./run.sh phase 1 && ./run.sh phase 2 && ./run.sh phase 3 && ./run.sh phase 4
   ```

4. Begin the next unstarted phase in [docs/phases.md](docs/phases.md), whose
   status table is the authoritative record of where the project is. Implement
   only that phase's scope.
5. Keep the user informed: state what is being built, name the directories being
   changed, explain why the change belongs to the current phase, and report
   validation results or blockers honestly.
