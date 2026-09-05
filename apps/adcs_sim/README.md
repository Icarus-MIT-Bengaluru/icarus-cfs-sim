# ADCS cFS App Placeholder

Intentionally empty until **Phase 4**, which adds the isolated `adcs_sim` cFS
application here with its own headers, source, CMake integration, startup entry,
command/telemetry definitions, event IDs, message IDs, configuration, and
unit-test scaffold.

This app owns the UDP adapter to the `adcs` controller (port 31001) and no
other. See [docs/phases.md](../../docs/phases.md)
and [docs/peripherals.md](../../docs/peripherals.md).
