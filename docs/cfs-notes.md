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

This is inherited vendor default behavior, not something ICARUS added.
[architecture.md](architecture.md#binding-constraints) excludes SBN by design,
and the Phase 4 mission overlay is the correct place to drop it and trim the app
set. Do not work around it by patching the submodule.

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

The Health and Safety app cannot reach host CPU-utilization counters from
inside the container. This does **not** prevent cFE reaching operational state,
so it is not a Phase 1/2 gate failure — but **Phase 6 depends on HS** and must
account for it explicitly rather than being surprised by it.

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
