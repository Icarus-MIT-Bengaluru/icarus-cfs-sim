# Payload cFS Application (`payload_sim`)

Phase 4 skeleton for the ICARUS Payload subsystem. **Simulation scaffolding, not
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
| Scheduled rate | 1 Hz (`PacketRate = 10`, 100 ms tick) |
| Topic-ID block | `0xc4`-`0xc7` (CMD `0xc4`, SEND_HK `0xc5`, HK_TLM `0xc6`) |
| Event-ID range | 21-39 |
| Performance ID | 121 |
| Device simulator | `payload:31002` — **this app addresses no other controller** |
| Command pipe | `PAYLOAD_SIM_CMD_PIPE` |

## Where to fill in

- `fsw/src/payload_sim.c` — `PAYLOAD_SIM_Wakeup()` is where periodic Payload work belongs.
  It runs at this app's scheduled rate (1 Hz), driven by `sch_lab`.
- `fsw/src/payload_sim_cmds.c` — command handler bodies and new housekeeping fields.
- `fsw/src/payload_sim_dispatch.c` — add command codes to the dispatch switch.
- `fsw/src/payload_sim_udp.c` — `PAYLOAD_SIM_UDP_Send()` and `PAYLOAD_SIM_UDP_Receive()` are stubs.
- `unit-test/coveragetest/coveragetest_payload_sim.c` — placeholder test.

New command codes go in `config/default_payload_sim_fcncode_values.h`, new event IDs
in `fsw/inc/payload_sim_eventids.h` (stay inside this app's range), and new topic IDs
in `fsw/inc/payload_sim_topicids.h` (stay inside this app's block).

## Rules

This app must not include another app's private headers, share globals, read
another app's files, or address another controller. Cross-app communication uses
cFS Software Bus messages only. See
[docs/architecture.md](../../docs/architecture.md).
