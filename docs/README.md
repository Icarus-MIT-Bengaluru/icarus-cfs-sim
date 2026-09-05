# ICARUS Documentation

Project documentation for `icarus-cfs-sim`, a containerized NASA cFS
simulation skeleton for a 1U CubeSat. **This is not flight software and must
not be presented as a flight-ready image.**

## Read in this order

| Document | What it covers |
|---|---|
| [architecture.md](architecture.md) | Fixed architecture, container topology, network, why SBN is excluded, scope boundaries and assumptions |
| [repository-layout.md](repository-layout.md) | Directory tree, what owns what, rules for making changes |
| [phases.md](phases.md) | The authoritative seven-phase development ladder and every phase gate |
| [build-and-run.md](build-and-run.md) | Host prerequisites, image build process, the full `run.sh` command surface |
| [cfs-notes.md](cfs-notes.md) | cFS-specific knowledge: the pinned bundle, `native_std`, mission-config overlay mechanism, known gotchas |
| [peripherals.md](peripherals.md) | The OBC-to-device-simulator interface: ports, UDP protocol contract, controller behavior |
| [testing.md](testing.md) | Test method, the logging contract, and the rules every phase test obeys |
| [status.md](status.md) | Current implementation state, validation record, and change log |

## Documentation rules

1. **One fact, one home.** Each document owns its subject. Cross-link instead
   of restating. If two documents disagree, the owning document wins.
2. **Document as-built, not as-wished.** These files describe what the code
   actually does. Intended-but-unimplemented behavior belongs in
   [phases.md](phases.md) under its assigned phase, marked as such.
3. **Update the docs in the same change as the code.** Any change to
   `run.sh`, the `Dockerfile`, the entrypoints, `apps/`, or controller
   configuration updates the affected document and adds a
   [status.md](status.md) change-log entry in the same pass.
4. **Record evidence, not claims.** A phase is passed when its gate command
   exits zero and its evidence exists on the host — see
   [testing.md](testing.md).

## Relationship to the original design briefs

These documents consolidate three overlapping source briefs (the summary
brief, the seven-phase plan, and the Phase 1 detail brief) plus the former
former root `AGENT_HANDOFF.md`. Where those sources conflicted, the conflicts were
resolved as recorded in [status.md](status.md#resolved-source-conflicts).
The consolidated documents are now authoritative; the original briefs are
superseded.
