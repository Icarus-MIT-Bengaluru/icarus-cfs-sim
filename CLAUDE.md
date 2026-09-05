# ICARUS — Working Rules

This repository builds a **containerized cFS development/simulation skeleton**
for a 1U CubeSat. It is not flight software and must not be presented as a
flight-ready image.

Full documentation: **[`docs/`](docs/README.md)**. Read
[docs/status.md](docs/status.md) before doing anything — it says which phase is
current and what is still open.

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
7. **Preserve the uncommitted work.** No destructive Git commands. Nothing in
   this repo has been committed yet.

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
   ./run.sh phase 1 && ./run.sh phase 2 && ./run.sh phase 3
   ```

4. Begin the next unstarted phase in [docs/phases.md](docs/phases.md), whose
   status table is the authoritative record of where the project is. Implement
   only that phase's scope.
5. Keep the user informed: state what is being built, name the directories being
   changed, explain why the change belongs to the current phase, and report
   validation results or blockers honestly.
