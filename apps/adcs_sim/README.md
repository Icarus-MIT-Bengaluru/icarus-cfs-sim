# ADCS cFS Application (`adcs_sim`)

Phase 4 skeleton for the ICARUS ADCS subsystem. **Simulation scaffolding, not
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
| Scheduled rate | 10 Hz (`PacketRate = 1`, 100 ms tick) |
| Topic-ID block | `0xc0`-`0xc3` (CMD `0xc0`, SEND_HK `0xc1`, HK_TLM `0xc2`) |
| Event-ID range | 1-19 |
| Performance ID | 120 |
| Device simulator | `adcs:31001` — **this app addresses no other controller** |
| Command pipe | `ADCS_SIM_CMD_PIPE` |

## Where to fill in

- `fsw/src/adcs_sim.c` — `ADCS_SIM_Wakeup()` is where periodic ADCS work belongs.
  It runs at this app's scheduled rate (10 Hz), driven by `sch_lab`.
- `fsw/src/adcs_sim_cmds.c` — command handler bodies and new housekeeping fields.
- `fsw/src/adcs_sim_dispatch.c` — add command codes to the dispatch switch.
- `fsw/src/adcs_sim_udp.c` — `ADCS_SIM_UDP_Send()` and `ADCS_SIM_UDP_Receive()` are stubs.
- `unit-test/coveragetest/coveragetest_adcs_sim.c` — placeholder test.

New command codes go in `config/default_adcs_sim_fcncode_values.h`, new event IDs
in `fsw/inc/adcs_sim_eventids.h` (stay inside this app's range), and new topic IDs
in `fsw/inc/adcs_sim_topicids.h` (stay inside this app's block).

## Rules

This app must not include another app's private headers, share globals, read
another app's files, or address another controller. Cross-app communication uses
cFS Software Bus messages only. See
[docs/architecture.md](../../docs/architecture.md).
