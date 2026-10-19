# Comms cFS Application (`comms_sim`)

Phase 4 skeleton for the ICARUS Comms subsystem. **Simulation scaffolding, not
flight software.**

## What exists

Real cFS app structure with deliberately minimal function bodies: registration,
EVS events, a Software Bus command pipe with subscriptions, a housekeeping
telemetry message, and this app's private UDP adapter. Every function is present
with its real signature so behaviour can be filled in without touching
integration.

## What this app owns

| Resource | Value |
|---|---|
| Scheduled rate | 0.1 Hz (`PacketRate = 100`, 100 ms tick) |
| Topic-ID block | `0xc8`-`0xcb` (CMD `0xc8`, SEND_HK `0xc9`, HK_TLM `0xca`) |
| Event-ID range | 41-59 |
| Performance ID | 122 |
| Device simulator | `comms:31003` — **this app addresses no other controller** |
| Command pipe | `COMMS_SIM_CMD_PIPE` |

## Where to fill in

- `fsw/src/comms_sim.c` — `COMMS_SIM_Wakeup()` is where periodic Comms work belongs.
  It runs at this app's scheduled rate (0.1 Hz), driven by `sch_lab`.
- `fsw/src/comms_sim_cmds.c` — command handler bodies and new housekeeping fields.
- `fsw/src/comms_sim_dispatch.c` — add command codes to the dispatch switch.
- `fsw/src/comms_sim_udp.c` — `COMMS_SIM_UDP_Send()` and `COMMS_SIM_UDP_Receive()` are stubs.
- `unit-test/coveragetest/coveragetest_comms_sim.c` — placeholder test.

New command codes go in `config/default_comms_sim_fcncode_values.h`, new event IDs
in `fsw/inc/comms_sim_eventids.h` (stay inside this app's range), and new topic IDs
in `fsw/inc/comms_sim_topicids.h` (stay inside this app's block).

## Rules

This app must not include another app's private headers, share globals, read
another app's files, or address another controller. Cross-app communication uses
cFS Software Bus messages only. See
[docs/architecture.md](../../docs/architecture.md).
