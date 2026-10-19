# Peripheral Interaction — OBC to Device Simulators

How the OBC talks to the three simulated subsystem controllers. The transport is
plain UDP over the private bridge; there is no cFS on the controller side.

> **Implementation status:** the transport is implemented and verified
> (Phase 3). What still does not exist is any cFS involvement — the OBC side is
> a standalone probe utility, not a cFS app. Phase 4 replaces the probe with
> per-app UDP adapters owned by `adcs_sim`, `payload_sim`, and `comms_sim`.

## Endpoint map

| Subsystem | Container | Network alias | UDP port | Owning cFS app (Phase 4) |
|---|---|---|---|---|
| ADCS | `icarus-adcs` | `adcs` | 31001 | `adcs_sim` |
| Payload | `icarus-payload` | `payload` | 31002 | `payload_sim` |
| Comms | `icarus-comms` | `comms` | 31003 | `comms_sim` |

Two files describe these endpoints, deliberately:

- `controllers/<name>/config/runtime.env` is authoritative for that
  controller's own identity and port.
- `controllers/obc/config/udp.env` is the OBC-side map: aliases, ports, the
  protocol prefixes, the token prefix, and the acknowledgement timeout.

`run.sh phase 3` cross-checks the two and **fails the gate if they disagree**,
so the duplication cannot silently drift.

## Addressing rules

- Containers resolve each other **by alias, never by IP.** Addresses on
  `icarus-net` are assigned by Docker and are not stable.
- **No controller port is published to the host.** The bridge is `--internal`,
  so all traffic and all tests stay inside the private network, driven from the
  OBC.
- **One app, one controller.** `adcs_sim` addresses only ADCS, `payload_sim`
  only Payload, `comms_sim` only Comms. The Phase 3 gate enforces this at
  transport level by failing if a token appears in more than one controller log.
- **Controllers never talk to each other.** The OBC is the only client.

## Protocol

Deliberately minimal — a placeholder hello/ack exchange, not a device protocol.

```
request   ICARUS|HELLO|<token>
response  ICARUS|ACK|<token>|<controller>
```

The token identifies one exchange, so a reply can be *matched* to its request
rather than merely observed. `run.sh` generates a per-run unique token per
route (`<prefix>-<UTC timestamp>-<controller>`).

Accepted input, enforced by the server:

| Rule | Limit |
|---|---|
| Maximum datagram | 512 bytes |
| Maximum token length | 128 bytes |
| Character set | printable ASCII (0x20–0x7E) only |
| Token content | non-empty, and may not contain `\|` |

Anything else is rejected with a reason and the server stays alive. The four
rejection reasons are `oversize`, `non-printable`, `bad-prefix`, and
`bad-token`. Oversize is detected with `recvfrom(MSG_TRUNC)`, which reports the
true datagram length rather than silently truncating.

## Components

### Controller echo server — `controllers/udp-echo-server.c`

One static binary serves all three controllers; identity and port come from
`CONTROLLER_NAME` and `CONTROLLER_UDP_PORT`, so the three containers stay
separately configured while sharing an image. It binds the port, handles **one
datagram at a time**, logs every receive, send, and rejection, and traps
`SIGTERM`/`SIGINT` to log a clean `STOP`. That last part only happens if the
container is stopped gracefully — a SIGKILL skips it, which is why `run.sh stop`
sends SIGTERM first.

It is statically linked because the controller runtime is BusyBox, which has no
libc. It performs no name resolution, so static linking costs nothing.

### OBC probe — `controllers/obc/tools/udp-probe.c`

A **transport test tool, not a cFS app and not a flight component.** It sends one
request to exactly one alias/port, waits with a bounded timeout, and returns
nonzero on any failure:

| Exit | Meaning |
|---|---|
| 0 | Acknowledgement received and matched exactly |
| 3 | Timed out waiting for a response |
| 4 | Response did not match the expected acknowledgement |
| 5 | Usage, resolution, or socket error |

It is dynamically linked on purpose: it needs glibc's resolver to turn a
container alias into an address, which a static glibc binary cannot do.

## Log format

Every line from both components is:

```
<UTC timestamp> <component> <EVENT> <key>=<value> ...
```

| Component | Events |
|---|---|
| Controller | `START`, `LISTEN`, `RX`, `TX`, `REJECT`, `ERROR`, `STOP` |
| OBC probe | `PROBE`, `ACK`, `PASS`, `FAIL` |

A verified exchange looks like this — note that the same token appears on both
sides, which is what makes the evidence conclusive:

```
# controllers/adcs/logs/controller.log
2026-09-05T20:49:00Z adcs RX src=172.19.0.2:45988 token=phase3-…-adcs payload=ICARUS|HELLO|phase3-…-adcs
2026-09-05T20:49:00Z adcs TX dst=172.19.0.2:45988 token=phase3-…-adcs payload=ICARUS|ACK|phase3-…-adcs|adcs

# controllers/obc/logs/udp-probe.log
2026-09-05T20:49:00Z obc ACK  target=adcs:31001 token=phase3-…-adcs response=ICARUS|ACK|phase3-…-adcs|adcs rtt_ms=0
2026-09-05T20:49:00Z obc PASS target=adcs:31001 token=phase3-…-adcs
```

## Evidence requirement

A link is proven only when **both ends** show it: the correct source,
destination, payload marker, and acknowledgement in the OBC probe log *and* in
that controller's own log. Seeing it on one side is not proof.

Per [architecture.md](architecture.md#binding-constraints), a successful UDP
exchange proves Docker transport only — it says nothing about cFS Software Bus
routing, which is a separate claim requiring separate evidence.

## Behavior worth knowing

**Two distinct controller failure signatures.** A *stopped* container and a
*disconnected* one are different faults and Phase 6 asserts both separately:

| Fault | Container | Alias | Probe result |
|---|---|---|---|
| `docker stop` | gone | withdrawn | exit 5, `resolve-failed` |
| `docker network disconnect` | alive | withdrawn from that network | nonzero; the container keeps running |

A timeout rather than a resolution failure means the container is *running but
not answering* — a third, different fault.

**A stopped controller fails as a name-resolution error, not a timeout.** Docker's
embedded DNS withdraws the alias as soon as the container stops, so the probe
returns exit 5 (`reason=resolve-failed`) rather than exit 3. Phase 6 and Phase 7
must expect that shape of failure when they stop a controller deliberately; a
timeout instead means the container is *running* but not answering, which is a
different fault.
