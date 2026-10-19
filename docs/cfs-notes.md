# cFS-Specific Notes

Knowledge about the NASA cFS framework that this project depends on. Everything
here was verified against the pinned bundle in `cfs/`.

## The pinned bundle

- `nasa/cFS` release **v7.0.1**, commit `088b2fa828db9ff7e00733f1908e0eeb59f66ce3`.
- All 25 nested submodules (cfe, osal, psp, apps/*, libs/*, tools/*) are pinned
  at their recorded commits.
- The submodule is **vendor code and is never edited.** See
  [repository-layout.md](repository-layout.md#rules-for-changes).

## The `native_std` target

`native_std` is cFS's supported native Linux development configuration. From
`cfs/target-configs.mk` it expands to:

```
-DENABLE_UNIT_TESTS=TRUE  -DSIMULATION=native  -DCFE_EDS_ENABLED=OFF
-DMISSIONCONFIG=sample    -DCMAKE_BUILD_TYPE=debug
```

Consequences worth knowing:

- `ENABLE_UNIT_TESTS=TRUE` means the build also compiles every app's coverage
  test runners, which is most of the build time and most of the staged
  `exe/cpu1/` file count.
- `MISSIONCONFIG=sample` selects `cfs/sample_defs/` as the mission definition
  directory. This is what Phase 4 replaces.
- `sample_defs/targets.cmake` builds both `cpu1` and `cpu2`. Only `cpu1` is
  staged into the OBC image.

**cFS must launch from the staged `exe/cpu1` directory**, because it locates its
startup script and dynamically loaded modules relative to that working path. The
OBC entrypoint therefore `cd`s there before running `./core-cpu1`.

## SBN loads by default

`sample_defs/targets.cmake` appends `sbn`, `sbn_udp`, and `sbn_f_remap` to
`MISSION_GLOBAL_APPLIST` for native non-EDS builds, and
`sample_defs/generate_startup.cmake` writes `sbn` into the generated
`cfe_es_startup.scr`. **The current OBC image therefore starts SBN**, along with
`cfe_assert`, `sample_lib`, `sch_lab`, `ci_lab`, `to_lab`, `sample_app`, `lc`,
`cf`, `ds`, `fm`, `hk`, `hs`, `mm`, `sc`, `md`, and `cs`.

This was inherited vendor default behaviour, not something ICARUS added.
**As of 2026-10-17 the ICARUS mission overlay removes it:** the startup script
went from 17 entries to 8 and the staged module set from 20 `.so` to 9. SBN,
`sample_app`, `sample_lib`, `cf`, `ds`, `fm`, `hk`, `lc`, `mm`, `sc`, `md` and
`cs` are no longer built. Retained: `sch_lab`, `hs`, `ci_lab`, `to_lab`,
`cfe_assert`. See
[the overlay README](../controllers/obc/config/mission/README.md).

## Mission overlay without touching the submodule

Phase 4 needs project-owned mission configuration. The mechanism, verified in
the cFS CMake sources:

1. **Mission defs directory.** `cfe/cmake/mission_build.cmake:80` sets
   `MISSION_DEFS = ${MISSION_SOURCE_DIR}/${MISSIONCONFIG}_defs`, and
   `MISSION_SOURCE_DIR` is the parent of the `-S` source dir — i.e.
   `/opt/icarus/cfs` in the builder image. So `MISSIONCONFIG=icarus` resolves to
   `/opt/icarus/cfs/icarus_defs/`, which the Dockerfile `COPY`s in as a build
   input. Nothing is written into the host's checked-out submodule.

2. **Selecting it.** `PREP_OPTS_native_std` is built with `+=` in
   `target-configs.mk`, but a **command-line variable assignment overrides
   in-makefile assignments** and propagates to the sub-make through `MAKEFLAGS`:

   ```sh
   make native_std.prep PREP_OPTS_native_std='-DENABLE_UNIT_TESTS=TRUE \
       -DSIMULATION=native -DCFE_EDS_ENABLED=OFF \
       -DMISSIONCONFIG=icarus -DCMAKE_BUILD_TYPE=debug'
   ```

3. **App sources outside the vendor tree.** The `CFS_APP_PATH` environment
   variable is prepended to `MISSION_MODULE_SEARCH_PATH`
   (`mission_build.cmake:380-384`). Relative entries resolve against
   `MISSION_SOURCE_DIR`, so the project apps can live in their own directory
   rather than inside `cfs/apps/`.

4. **The startup script hook.** `sample_defs/cpu1/install_custom.cmake` is what
   calls `generate_cfs_startup_script(...)` and registers extra tables. The
   ICARUS equivalent belongs at `icarus_defs/cpu1/install_custom.cmake`.

## Writing a cFS app for this project

Three things cost real debugging time when the Phase 4 apps were added. All
three fail in ways that do not obviously point at the cause.

### Both `arch_build.cmake` and `mission_build.cmake` are required

Each declares a different scope of generated config header:

| File | Declares |
|---|---|
| `arch_build.cmake` | Platform scope: `*_internal_cfg_values.h`, `*_platform_cfg.h`, `*_perfids.h`, `*_msgids.h`, `*_msgid_values.h` |
| `mission_build.cmake` | Mission scope: `*_fcncode_values.h`, `*_interface_cfg_values.h`, `*_mission_cfg.h`, `*_msg.h`, `*_msgdefs.h`, `*_msgstruct.h`, `*_topicid_values.h` |

Omit `mission_build.cmake` and the app still compiles, but any **table** that
includes its msgids fails with `*_topicid_values.h: No such file or directory`.

### Names are capped at 20 characters, including the null

`OSAL_CONFIG_MAX_API_NAME` is 20. A pipe name of exactly 20 characters makes
`CFE_SB_CreatePipe` fail with `OS_QueueCreate returned -13`, which is
`OS_ERR_NAME_TOO_LONG` — not a resource error, despite looking like one. The
app then exits while its siblings start normally, which makes it look like a
race. Keep pipe names at 19 characters or fewer.

### Mission defs override an app's own table source

`cfe_locate_implementation_file` searches `${MISSION_DEFS}/` and
`${MISSION_DEFS}/tables/` **before** the app's own `fsw/tables/`. So dropping
apps from the build requires replacing the stock `sch_lab_table.c` and
`to_lab_sub.c` in the overlay: the vendor versions `#include` msgid headers
from every sample app and will not compile without them. The same applies to
`cpu1/install_custom.cmake`, which references each app as a CMake target.

## Scheduling and time (Phase 5)

### `sch_lab` tick arithmetic

The table's `TickRate` sets the timer period as `1000000 / TickRate`
microseconds, and each entry fires every `PacketRate` ticks. With
`TickRate = 10` the tick is **100 ms**, so an entry's period is
`PacketRate × 100 ms`:

| `PacketRate` | Period | Rate |
|---|---|---|
| 1 | 100 ms | 10 Hz |
| 10 | 1.0 s | 1 Hz |
| 100 | 10.0 s | 0.1 Hz |

100 ms is an exact multiple of the 10 ms PSP soft timebase, so there is no
sub-tick quantization. Stick to `TickRate` values that divide into a multiple of
10 ms (1/2/5/10/20/25/50/100); anything else is quantized and averaged.

**Long-run drift is zero.** The tick comes from a `CLOCK_MONOTONIC` periodic
timer, and OSAL's dispatcher *accumulates* (`wait_time += interval_time`) rather
than resetting, so quantization error does not build up.

**But ticks bunch.** The handoff to the app is a *counting* semaphore, so if
`sch_lab` is briefly descheduled the queued ticks are consumed back-to-back.
Two sends can legitimately appear far closer together than the nominal period.
Measure the **mean** tightly and the **instantaneous** period loosely, and never
assert a minimum interval.

**Startup transient.** Nothing is sent until the first `CFE_TIME` 1 Hz packet
arrives, and each entry's first send is `PacketRate` ticks after that. Discard
the first interval of every entry.

Capacity is 32 entries and 32 argument words
(`DEFAULT_SCH_LAB_MISSION_MAX_SCHEDULE_ENTRIES`); ICARUS uses 14.

### A scheduled MID must be a command MID

`sch_lab` sizes a scheduled packet as
`sizeof(CFE_MSG_CommandHeader_t) + PayloadLength` (8 bytes when
`PayloadLength` is 0) and applies the entry's `FcnCode` with
`CFE_MSG_SetFcnCode`, which **silently fails on a telemetry MID**. A TLM wakeup
would be transmitted claiming an 8-byte header while the receiver expects 16,
and SB does not catch it. Derive wakeup MIDs with
`CFE_PLATFORM_CMD_TOPICID_TO_MIDV`, never the TLM variant.

### Use a single monotonic integer for timing, not `CFE_TIME_SysTime_t`

For measuring rates, read `CFE_PSP_GetTime()` into an `OS_time_t` and convert
with `OS_TimeGetTotalMicroseconds()` — one `int64`, so it cannot tear. On this
target `CFE_PSP_GetTime` is `clock_gettime(CLOCK_MONOTONIC)`. cFE's own SB, EVS
and TIME modules use it, so this is idiomatic.

Avoid the alternatives:

- `CFE_TIME_GetTime()` is the ground-commandable TAI/UTC clock and can jump.
- `CFE_TIME_GetMET()` returns a `{Seconds, Subseconds}` pair. In this build its
  subseconds were observed wrapping **without the seconds field carrying**,
  which produced negative intervals — so the split value was unusable for
  interval math even from a single snapshot.
- `CFE_TIME_GetMETseconds()` / `GetMETsubsecs()` take independent snapshots and
  can tear across a second boundary. Never call them as a pair.

### EVS rate-limits events per app

`CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC` is **15** per app with a burst of 32.
A 10 Hz app emitting one event per wakeup uses 10 — only 50% headroom, so emit
**exactly one** event per wakeup. Exceeding it logs
`Events squelched, AppName = ...` and silently drops events, which would make
any rate measurement unsound. `run.sh phase 5` asserts no squelching occurred.

### Console output is asynchronous

`OSAL_CONFIG_CONSOLE_ASYNC` defaults `TRUE`: `OS_printf` queues into a ring that
a separate task drains, so **console lines are delivered in bursts**. Observed:
three events whose own timestamps were 5–6 s apart arriving within 0.4 ms of
each other, then 84 s of silence.

Consequences:

- **Never infer timing from when a log line appeared.** Embed a timestamp in the
  message itself.
- A marker's absence from the log does not mean the event did not happen — it
  may still be queued. Poll for a sample count with a generous deadline.
- Log-polling waits need large timeouts; this is why
  `OBC_STARTUP_TIMEOUT_SECONDS` is 120.

## ES application restart (Phase 7)

`CFE_ES_RESTART_APP` is MID `0x1806`, **function code 6**.

**It is a two-stage, deferred operation.** The command only sets
`ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART`. The ES background
task then moves the app to `WAITING` and counts down
`APP_KILL_TIMEOUT (5) × APP_SCAN_RATE (1000 ms)` = **5 s** before acting, so
budget well over that — a 2 s assertion will flake against a perfectly good
restart.

**It restarts a hard-blocked task.** ES does not wait for cooperation: it calls
`OS_TaskDelete`, which is `pthread_cancel` + `pthread_join`, and
`OS_TaskDelay`'s `clock_nanosleep` is a POSIX cancellation point with deferred
cancellation armed at task entry. **Verified:** an app deliberately blocked in
`OS_TaskDelay` forever is cleanly restarted. This matters because that is the
only stall HS can detect, and it is therefore recoverable at app scope.

**There is no "app failed to exit in time" event.** Do not assert on one; it
does not exist in this cFE. ES simply waits out the timeout and force-deletes.

**The restart is a full module reload** — `OS_ModuleUnload` then
`CFE_ES_LoadModule` — producing a **new AppID**, so the app's globals are
re-initialised. Observable consequence worth asserting on: a restarted ICARUS
app resumes at `wakeup seq=1`, which proves its state was genuinely reset
rather than the restart being a no-op.

**`Completed` does not mean the app is up.** `CFE_ES_RESTART_APP_INF_EID` fires
as soon as the new main task is *spawned*; the app's `Init` may still fail
afterwards. Always additionally assert the app's own startup event and that it
resumes work at its declared rate.

**Pipes and sockets are reclaimed.** `CFE_SB_CleanUpApp` deletes every pipe
owned by the AppID (freeing the fixed name), and the OSAL object sweep closes
`OS_STREAM` handles, so a UDP socket is released too. The failure to watch for
is `CreatePipeErr:OS_QueueCreate failed, name taken`, which would make the
restarted app die in `Init`.

Two text gotchas found by running it:

- The observable "initiated" line is the **SysLog** form
  `CFE_ES_RestartApp: Restart Application X Initiated` — **no trailing
  period**. The EVS DEBUG event that has the period is filtered out by the
  default event-type mask.
- Restarting a *healthy* app produces a spurious
  `SB pipe read error, app will exit` from the app, because its pending
  `CFE_SB_ReceiveBuffer` is cut off when the pipe is deleted microseconds
  before the task. That is normal during a restart, not a recovery failure.

### A commanded processor reset kills the OBC here

`CFE_ES_RESTART` → `CFE_PSP_Restart` returns from `main` and the process exits.
The entrypoint runs `core-cpu1` exactly once and no Docker restart policy is
set, so a commanded processor reset leaves the OBC **permanently dead**, not
rebooted. Restart the container instead.

For the same reason **`HS_AMTActType_PROC_RESET` must never appear in the AMT** —
HS would kill the OBC with no recovery path.

### HS monitors must be re-armed after a recovery

An AMT countdown is never rewritten by the monitor, so once an entry fires the
app is no longer watched — a restarted app is unmonitored until re-armed.
Re-arming is `HS_DISABLE_APP_MON_CC` (3) **then** `HS_ENABLE_APP_MON_CC` (2) on
`HS_CMD_MID` `0x18AE`. Enabling while already enabled refreshes nothing and
logs `Application Monitoring is *already* Enabled` — treat that as a **failed
re-arm**, not a success. Verified: EID 26 then EID 25 on the pair, and the
`*already*` line when `ENABLE` is sent alone.

## Known gotchas

### POSIX message queues

The cFS native Linux target needs a raised message-queue limit. The OBC
container is launched with `--sysctl fs.mqueue.msg_max=64`. Without it, cFE
fails during startup. Raise it if cFE ever asks for more.

### HS system monitor fails in a container

At every boot the console shows:

```
HS_SysMonInit(): Unable to start device 0110ff05
EVS Port1 .. 66/1/HS 74: Error in system monitor initialization, RC=0xC8000005
```

The `linux_sysmon` PSP module opens `/proc/schedstat`, which the container
kernel does not provide usably, so `CFE_PSP_IODriver_SET_RUNNING` fails and
`HS_AppInit` returns early.

**What still works:** `HS_AppMain` never sets `RunStatus = APP_ERROR`, so the
monitoring loop runs and `CurrentAppMonState` defaults to `ENABLED`.
**Application monitoring is fully intact** — this is what Phase 6 uses.

**What is silently lost** (everything inside the skipped `HS_AppInit` block):

| Lost | Consequence |
|---|---|
| CPU utilisation + hogging detection | No CPU-hog fault detection. Do not claim it. |
| **Watchdog arming** (`CFE_PSP_WatchdogSet/Service/Enable`) | The HS watchdog boundary is non-functional; `HS_ProcessMain` services an unarmed watchdog |
| `CFE_ES_WaitForStartupSync` | HS begins monitoring immediately at load |
| EVS event-message subscription | Only matters for the Event Monitor, which is disabled by default anyway |
| `HS_INIT_INF_EID` "HS Initialized" | Its absence is expected; not a separate failure |

Phase 6 documents the first two as **out of scope** rather than claiming them.

### Configuring the HS application monitor table

Rules that silently break the AMT if violated — all learned the hard way:

- **`AppName` must be the ES-registered name, which is UPPERCASE** here
  (`ADCS_SIM`, not `adcs_sim`); it is matched with `CFE_ES_GetAppIDByName`. A
  lowercase name still validates as "good" at load time and then produces
  `App Monitor App Name not found` forever at runtime.
- **`NullTerm` must be literally `0`** or `HS_ValidateAMTable` rejects the whole
  table and application monitoring is disabled outright.
- **`HS_AMTActType_NOACT` is not "event only"** — it disables the entry and HS
  never looks the app up. The observe-only action is `HS_AMTActType_EVENT` (3).
  `APP_RESTART` (2) takes recovery action and belongs to Phase 7.
- **`CycleCount` must exceed the app's own wake period.** HS compares the ES
  execution counter, which only advances when the app wakes. ICARUS uses 20
  against a 1.0 s HS cycle (~20 s) because `comms_sim` wakes only every 10 s;
  the stock 10 would trip it falsely.
- **Entries are one-shot.** The countdown is not re-armed after firing, so an
  entry reports once per table load. Restart the OBC (or issue
  `HS_AppMonStatusRefresh`) between successive fault injections.
- **A monitored app needs no code changes.** `CFE_ES_RunLoop` calls
  `CFE_ES_IncrementTaskCounter()` unconditionally, so a stall must stop the app
  re-entering the run loop — returning early from its work handler leaves the
  counter advancing and HS detects nothing.
- **The Event Monitor Table cannot observe without acting**: its action enum has
  no event-only option, so every non-zero action triggers recovery. Unusable
  for an observe-only phase.

Only the AMT is required; a missing EMT/MAT/XCT degrades gracefully. Verify HS
is really monitoring by checking for `AppMon verify results: good = N, bad = 0`
and the absence of `Application Monitoring Disabled`.

### cFE event time is not wall-clock time

`cfe-evs.log` lines carry cFE mission-elapsed time, e.g. `1980-012-14:03:20`,
not UTC. The console log's own ICARUS-written lines and every controller log use
real UTC. The [logging contract](testing.md#logging-contract) asks for UTC, so
reconciling cFE TIME with wall clock is an open item for the first phase that
needs cross-log correlation — Phase 5 rate checking most of all.

### Build cost

The full `native_std` build compiles ~15 apps plus all coverage test runners.
The cFS wrapper passes no `-j`, so the inner build is serial by default. If
build time becomes a problem, `-j"$(nproc)"` can be passed to the builder
`make`: the `.NOTPARALLEL` directive in the cFS top-level Makefile does not
strip `-j` from the inner sub-make.
