# OBC Mission Configuration

Reserved for the ICARUS-owned cFS mission overlay: app registration, message
IDs, event IDs, scheduler tables, and UDP endpoint settings.

**Empty until Phase 4.** Phases 1-3 run cFS's unmodified `native_std`
configuration staged from the pinned bundle.

The overlay must be integrated as a Docker build input rather than by editing
the `cfs/` submodule. The mechanism — `MISSIONCONFIG`, `CFS_APP_PATH`, and the
`install_custom.cmake` startup hook — is documented in
[docs/cfs-notes.md](../../../../docs/cfs-notes.md#mission-overlay-without-touching-the-submodule).
