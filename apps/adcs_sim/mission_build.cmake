###########################################################
#
# ADCS_SIM mission build setup
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

set(ADCS_SIM_MISSION_CONFIG_FILE_LIST
  adcs_sim_fcncode_values.h
  adcs_sim_interface_cfg_values.h
  adcs_sim_mission_cfg.h
  adcs_sim_perfids.h
  adcs_sim_msg.h
  adcs_sim_msgdefs.h
  adcs_sim_msgstruct.h
  adcs_sim_topicid_values.h
)

generate_configfile_set(${ADCS_SIM_MISSION_CONFIG_FILE_LIST})
