###########################################################
#
# PAYLOAD_SIM mission build setup
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

set(PAYLOAD_SIM_MISSION_CONFIG_FILE_LIST
  payload_sim_fcncode_values.h
  payload_sim_interface_cfg_values.h
  payload_sim_mission_cfg.h
  payload_sim_perfids.h
  payload_sim_msg.h
  payload_sim_msgdefs.h
  payload_sim_msgstruct.h
  payload_sim_topicid_values.h
)

generate_configfile_set(${PAYLOAD_SIM_MISSION_CONFIG_FILE_LIST})
