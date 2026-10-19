###########################################################
#
# COMMS_SIM mission build setup
#
# Evaluated during the "prepare" stage. Declares the
# mission-scope config headers generated from this app's
# config/ defaults. The platform-scope set is in
# arch_build.cmake.
#
# No cFE tables in the Phase 4 skeleton, so the tbl/tbldefs/
# tblstruct headers the cFS sample declares are absent here.
#
###########################################################

set(COMMS_SIM_MISSION_CONFIG_FILE_LIST
  comms_sim_fcncode_values.h
  comms_sim_interface_cfg_values.h
  comms_sim_mission_cfg.h
  comms_sim_perfids.h
  comms_sim_msg.h
  comms_sim_msgdefs.h
  comms_sim_msgstruct.h
  comms_sim_topicid_values.h
)

generate_configfile_set(${COMMS_SIM_MISSION_CONFIG_FILE_LIST})
