# Architecture

## Purpose and scope

ICARUS builds a **containerized cFS development/simulation skeleton** for a 1U
CubeSat. It exists to prove infrastructure properties — lifecycle, isolated
logs, private networking, UDP transport, cFS application separation, scheduler
behavior, fault containment, and recovery — using placeholder hello/ack
behavior only.

**Out of scope unless the user explicitly expands it:** ADCS control laws,
payload processing, radio protocols, EPS, hardware drivers, and any mission
algorithm. Placeholder means placeholder.

## Container topology

```text
                     internal Docker bridge: icarus-net

  +---------------------+       +---------------------+
  |  icarus-obc         | UDP   |  icarus-adcs        |
  |  Debian bookworm    +------>+  BusyBox simulator  |
  |  one cFS instance   |       |  reserved :31001    |
  |                     |       +---------------------+
  |  adcs_sim app       |
  |  payload_sim app    |       +---------------------+
  |  comms_sim app      | UDP   |  icarus-payload     |
  +---------------------+------>+  BusyBox simulator  |
           |                    |  reserved :31002    |
           |                    +---------------------+
           |
           |                    +---------------------+
           +------------------->+  icarus-comms       |
                          UDP   |  BusyBox simulator  |
                                |  reserved :31003    |
                                +---------------------+
```

## Binding constraints

These are architectural decisions, not preferences. Changing any of them is a
change in project direction and requires the user's agreement.

1. **OBC is the only cFS node.** ADCS, Payload, and Comms are lightweight
   device-simulator containers. They do not run cFS.
2. **SBN is excluded.** The Software Bus Network app bridges *separate* cFS
   instances. With one cFS instance there is nothing to bridge, so SBN adds
   confusion and attack surface for no benefit. The OBC apps use a simple UDP
   simulator protocol instead — see [peripherals.md](peripherals.md).
   (The stock cFS mission config loads SBN by default; removing it is Phase 4
   work — see [cfs-notes.md](cfs-notes.md#sbn-loads-by-default).)
3. **The cFS Software Bus is used only inside the OBC**, from Phase 4 onward.
   UDP is the OBC-to-simulator transport. These two are never conflated:
   proving a UDP packet arrived is not proving SB routing.
4. **The three subsystems stay separate cFS applications** even though all
   three run in one OBC. They must not be merged into one app, share globals,
   include one another's private headers, read one another's files, or address
   another subsystem's controller. Cross-app communication uses cFS SB message
   types only.
5. **`icarus-net` is an internal bridge** (`--internal`), so there is no route
   to the host or the outside world and **no controller UDP port is published
   to the host**. Containers resolve one another by the network aliases `obc`,
   `adcs`, `payload`, and `comms`. All tests run inside the private bridge.
6. **The OBC is the only client of controller UDP ports.** No controller ever
   talks to another controller.

## Assumptions

- Debian slim is the OBC container base; BusyBox musl is the controller base.
  (An earlier brief described a single shared Debian image for both roles. The
  as-built split keeps controller builds independent of the cFS toolchain and
  is the design of record.)
- The OBC owns all three cFS applications.
- The controller containers are UDP device simulators, not cFS nodes.
- The existing folder tree is the top-level project layout; configuration,
  launch metadata, and logs stay inside their existing directories.
- `run.sh` is the sole orchestration interface. No `docker-compose` or second
  entry point is introduced without a stated change in direction.

## Completion criteria

The project is complete when Phase 7 passes end to end: one OBC cFS instance
runs three isolated placeholder apps; each has a verified UDP path to its own
independently managed simulator; all logs are separated and persistent;
scheduled activity is validated against declared rates; and failures can be
observed, isolated, and recovered. See [phases.md](phases.md).
