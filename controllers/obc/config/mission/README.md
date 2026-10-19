# ICARUS Mission Configuration Overlay

Project-owned cFS mission configuration. It **overlays** `cfs/sample_defs/`
rather than replacing it: the Docker build copies `sample_defs` to
`icarus_defs`, then copies these files over the top. Only files ICARUS actually
changes live here, and the `cfs/` submodule is never edited.

Selected with `-DMISSIONCONFIG=icarus`, which makes cFS resolve
`MISSION_DEFS` to `icarus_defs`.

## Files

| File | Purpose |
|---|---|
| `targets.cmake` | Mission name, spacecraft ID, the app list, and the single CPU. Registers the three ICARUS apps and drops SBN plus ten unused stock apps |
| `generate_startup.cmake` | Writes `cfe_es_startup.scr`. Loads the three ICARUS apps as separate modules with their own entry points |
| `cpu1/install_custom.cmake` | Table include paths and the startup-script hook. Replaces the sample version, which referenced eleven apps ICARUS does not build |
| `tables/sch_lab_table.c` | Scheduler table. Housekeeping only in Phase 4 — the rate-controlled wakeups are Phase 5 |
| `tables/to_lab_sub.c` | Telemetry-output subscriptions, including the three ICARUS housekeeping messages |

`MISSION_DEFS/tables/` takes priority over an app's own table source, so the two
table files here are the active ones for `sch_lab` and `to_lab`.

## Applications

**ICARUS:** `adcs_sim`, `payload_sim`, `comms_sim` — separate cFS apps with
non-overlapping topic-ID and event-ID blocks. See each app's README under
`apps/`.

**Retained stock:** `hs` (Phase 6), `sch_lab` (Phase 5), `ci_lab` + `to_lab`
(command and telemetry path), `cfe_assert`.

**Excluded:** `sbn` — it bridges separate cFS instances and the OBC is the only
one; see [docs/architecture.md](../../../../docs/architecture.md). Also unbuilt:
`cf`, `ds`, `fm`, `hk`, `lc`, `mm`, `sc`, `md`, `cs`, `sample_app`,
`sample_lib`.

Adding an app back means adding it to `targets.cmake`, to the startup script,
and — if `sch_lab` or `to_lab` should see its messages — to the two tables.

## Recovery order (Phase 7)

Recovery escalates through three scopes, **least disruptive first**:

| Rung | Scope | Mechanism | Fixes | Cannot fix |
|---|---|---|---|---|
| 1 | One app | `CFE_ES_RESTART_APP` by ground command | A stalled, hung or exited app, including a task hard-blocked in `OS_TaskDelay` — ES force-cancels it | Anything in cFE core, the schedule, or outside the OBC |
| 2 | One controller | `docker start` the named container | A stopped or crashed device simulator | An OBC-side fault; the app keeps its own state |
| 3 | The OBC | restart the `icarus-obc` container | cFE core state, the schedule, all app state at once | A controller fault; controllers deliberately stay up |

Always try the lowest rung that can fix the fault. Restarting the OBC to clear
one stalled app discards two healthy apps and the whole schedule for no reason.

**Rung 3 is a container restart, not a cFE processor reset.** In this
containerised pc-linux PSP, `CFE_ES_RESTART` returns from `main` and the
process exits; the entrypoint runs `core-cpu1` exactly once and no Docker
restart policy is set, so a commanded processor reset leaves the OBC
**permanently dead** rather than rebooting it. For the same reason
`HS_AMTActType_PROC_RESET` must never appear in `tables/hs_amt.c` — HS would
kill the OBC with no recovery path. The AMT stays on `HS_AMTActType_EVENT` so
detection and action remain separable.

**HS app monitors are one-shot and must be re-armed after a recovery.** The
countdown is never rewritten by the monitor, so a restarted app is no longer
watched. Re-arming requires `HS_DISABLE_APP_MON_CC` (3) **then**
`HS_ENABLE_APP_MON_CC` (2) on `HS_CMD_MID` 0x18AE — enabling while already
enabled logs `Application Monitoring is *already* Enabled` and refreshes
nothing.
