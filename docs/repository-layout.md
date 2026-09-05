# Repository Layout and Ownership

## Tree (as built)

```text
icarus-cfs-sim/
├── CLAUDE.md                      # Working rules; auto-loaded by Claude Code
├── README.md                      # Short human setup guide
├── Dockerfile                     # Multi-stage: controller + cFS builder + obc
├── run.sh                         # Only supported lifecycle/test interface
├── .gitmodules                    # Pins the cFS bundle revision
├── .gitignore / .dockerignore     # Exclude logs, build trees, vendor .git
│
├── docs/                          # This documentation set
│
├── cfs/                           # NASA cFS v7.0.1 vendor submodule; do not edit
│
├── controllers/
│   ├── controller-entrypoint.sh   # Shared controller entrypoint (all three sims)
│   ├── udp-echo-server.c          # Shared UDP device simulator (static binary)
│   ├── obc/
│   │   ├── config/
│   │   │   ├── entrypoint.sh      # Starts core-cpu1, persists console log
│   │   │   ├── runtime.env        # OBC image, timeout, network name
│   │   │   ├── udp.env            # OBC-side UDP endpoint map
│   │   │   └── mission/           # Project-owned cFS mission overlay (Phase 4)
│   │   ├── tools/
│   │   │   └── udp-probe.c        # OBC transport probe (not a cFS app)
│   │   └── logs/                  # cFE/app/phase evidence; bind-mounted to OBC
│   ├── adcs/
│   │   ├── config/runtime.env     # icarus-adcs, UDP port 31001
│   │   └── logs/                  # ADCS simulator log mount
│   ├── payload/
│   │   ├── config/runtime.env     # icarus-payload, UDP port 31002
│   │   └── logs/                  # Payload simulator log mount
│   └── comms/
│       ├── config/runtime.env     # icarus-comms, UDP port 31003
│       └── logs/                  # Comms simulator log mount
│
└── apps/
    ├── adcs_sim/                  # Phase 4 project-owned cFS app source
    ├── payload_sim/               # Phase 4 project-owned cFS app source
    └── comms_sim/                 # Phase 4 project-owned cFS app source
```

Directories for later phases exist now to establish the final layout. They
stay intentionally inactive until their assigned phase — see
[phases.md](phases.md).

## What each element is for

| Path | Role |
|---|---|
| `.gitmodules` | Pins the cFS source revision so every developer and CI run builds the same framework version |
| `Dockerfile` | A build stage compiles cFS; a lean runtime stage executes the OBC. A separate BusyBox stage builds the controller image |
| `run.sh` | Builds, starts, stops, inspects, and phase-tests every container |
| `controllers/<name>/config/runtime.env` | Authoritative source for that container's identity, image, and port. Non-secret configuration only |
| `controllers/obc/config/udp.env` | The OBC-side UDP endpoint map: aliases, ports, protocol prefixes, token prefix, timeout. Cross-checked against every `runtime.env` by the Phase 3 gate |
| `controllers/obc/tools/` | Project-owned OBC utilities that are **not** cFS apps. Currently the transport probe |
| `controllers/udp-echo-server.c` | The shared device-simulator server. Reusable controller source belongs here, not under one controller |
| `controllers/obc/config/mission/` | ICARUS-owned cFS configuration: app registration, message IDs, scheduler tables, UDP endpoint settings. Empty until Phase 4 |
| `controllers/*/logs/` | Host-mounted persistent evidence. Generated files are Git-ignored except `.gitkeep` |
| `apps/<name>_sim/` | Exactly one independently built cFS application each |

## Rules for changes

1. **Never edit `cfs/`.** It is an unmodified vendor submodule. Integrate
   custom applications and configuration through a project-owned mission
   overlay and Docker build inputs — see
   [cfs-notes.md](cfs-notes.md#mission-overlay-without-touching-the-submodule).
   Never copy project code into the checked-out submodule on the host.
2. **Keep controller-specific configuration and logs in that controller's own
   folder.** Never write one component's evidence into another's directory.
3. **Reusable simulator source goes in `controllers/`**; each custom cFS app
   goes only in its matching `apps/<name>_sim/`.
4. **Extend `run.sh`.** Do not introduce a competing orchestration interface.
5. **Update `docs/` in the same change**, per the rules in
   [README.md](README.md#documentation-rules).
