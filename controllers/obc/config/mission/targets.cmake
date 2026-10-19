##########################################################################
#
# ICARUS mission target configuration
#
# Overlays cfs/sample_defs/. Only the files ICARUS actually changes live
# here; everything else is inherited. The cfs/ submodule is never edited.
#
##########################################################################

SET(MISSION_NAME "ICARUS")

# Spacecraft ID: 'I' for ICARUS.
SET(SPACECRAFT_ID 0x49)

##########################################################################
# ICARUS subsystem applications
#
# All three run in the single OBC and stay separate cFS applications. See
# docs/architecture.md for the separation rules they must obey.
##########################################################################
list(APPEND MISSION_GLOBAL_APPLIST adcs_sim payload_sim comms_sim)

##########################################################################
# Stock cFS applications retained
#
#   hs       - Health and Safety monitoring, required by Phase 6
#   sch_lab  - scheduler, required by Phase 5
#   ci_lab   - command ingest, gives an interactive command path
#   to_lab   - telemetry output, gives an interactive telemetry path
#
# Deliberately NOT built: sbn (excluded by architecture -- it bridges
# separate cFS instances and there is only one), and cf, ds, fm, hk, lc,
# mm, sc, md, cs, sample_app, sample_lib (unused by any ICARUS phase).
##########################################################################
LIST(APPEND MISSION_GLOBAL_APPLIST hs)

# OBC is the only cFS node, so there is exactly one CPU.
SET(MISSION_CPUNAMES cpu1)

SET(cpu1_PROCESSORID 1)
SET(cpu1_APPLIST ci_lab to_lab sch_lab)
SET(cpu1_SYSTEM riscv64-poky-linux)

if (CFE_EDS_ENABLED)
   set(cpu1_PLATFORM default)
endif (CFE_EDS_ENABLED)
