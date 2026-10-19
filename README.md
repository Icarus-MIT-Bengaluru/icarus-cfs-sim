# ICARUS

This repository contains the ICARUS cFS simulation skeleton.

ICARUS is a containerized simulation of a 1U CubeSat flight-software stack built
on [NASA's Core Flight System](https://github.com/nasa/cFS). A single cFS
on-board computer hosts the subsystem applications, while ADCS, payload, and
communications are modelled as independently managed device simulators reachable
over UDP on a private Docker network.

## Building ICARUS

Docker is the official build system for ICARUS; the cFS `native_std` target
cannot be built directly on macOS or Windows because it requires the Linux PSP.

`run.sh` is the only supported interface for building, running, and testing the
containers:

```sh
git submodule update --init --recursive
./run.sh phase 3
```

The [ICARUS Build and Run Guide](docs/build-and-run.md) contains information on
host prerequisites, the image build stages, and every supported command.

## Documentation

All users of ICARUS should consult the following documentation resources:

*   The [ICARUS Architecture Guide](docs/architecture.md) covers the container
    topology, the constraints that are fixed by design, and the boundaries of
    what this project does and does not simulate.
*   The [ICARUS Phase Plan](docs/phases.md) covers the seven-phase development
    ladder, the exit gate for each phase, and which phases are complete.
*   The [ICARUS Build and Run Guide](docs/build-and-run.md) covers prerequisites,
    the image build, the `run.sh` command surface, and runtime configuration.
*   The [ICARUS Status Report](docs/status.md) covers the current state of the
    implementation, the validation record for each gate, and open items.

More advanced usages of ICARUS may find the following documentation useful:

*   The [ICARUS Repository Layout](docs/repository-layout.md) covers the
    directory tree, what owns what, and the rules governing changes.
*   The [ICARUS Peripheral Interface](docs/peripherals.md) covers the UDP
    protocol between the on-board computer and the device simulators, including
    the endpoint map, the log format, and the rejection rules.
*   The [ICARUS cFS Notes](docs/cfs-notes.md) cover the pinned cFS bundle, the
    mission-configuration overlay mechanism, and the framework gotchas this
    project has hit. Most contributors will not need this level of detail.
*   The [ICARUS Testing Guide](docs/testing.md) covers the test method, the
    logging contract every component obeys, and what counts as evidence.

Contributors and coding agents should start with [CLAUDE.md](CLAUDE.md), which
documents the rules this project is developed under.

## Status

**All seven phases are implemented and verified, and the project meets its
completion criteria.** The seven gates were last re-run in sequence on
2026-10-19, followed by a 68-assertion sweep of one live stack.

*   **Phases 1-3** — one cFS instance reaches operational state; four
    containers run independently on an internal bridge with separate persistent
    logs; the on-board computer completes a verified UDP hello/ack exchange with
    each of the three simulators.
*   **Phase 4** — `adcs_sim`, `payload_sim` and `comms_sim` run as separate cFS
    applications with their own message IDs, event IDs, logs and UDP routes. The
    mission overlay removes SBN, and isolation is proven: disabling one app
    leaves the other two and their controller links running.
*   **Phase 5** — `sch_lab` drives each app's periodic activity at a documented
    rate of 10 Hz, 1 Hz and 0.1 Hz, and the measured rates land within 0.1% of
    nominal.
*   **Phase 6** — six faults (app stall, app exit, controller stop, controller
    disconnect, malformed input, and an unavailable log mount) are each injected
    independently and shown to be detected, attributed and contained without
    affecting unrelated components.
*   **Phase 7** — a stalled app is recovered by Executive Services ground
    command, a stopped controller by restarting its container, and the OBC by
    restarting its own; each returns to nominal without duplicate app
    registrations or an image rebuild, and a recovery that cannot succeed stays
    visibly degraded rather than reporting normal.

The application function bodies are deliberate skeletons, ready to be filled in:
the gates prove integration, isolation, scheduling, fault containment and
recovery, not subsystem behaviour. CPU-hog detection and watchdog arming are not
available in this container and are not claimed. See the
[ICARUS Status Report](docs/status.md).

## License

No license has been declared for this repository yet.

Disclaimer: This is a development and simulation skeleton. It is not flight
software and must not be flown.
