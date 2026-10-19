###########################################################
#
# COMMS_SIM platform build setup
#
# Evaluated during the "prepare" stage. Generates the concrete
# config headers from this app's config/ defaults.
#
###########################################################

set(COMMS_SIM_PLATFORM_CONFIG_FILE_LIST
  comms_sim_internal_cfg_values.h
  comms_sim_platform_cfg.h
  comms_sim_perfids.h
  comms_sim_msgids.h
  comms_sim_msgid_values.h
)

generate_configfile_set(${COMMS_SIM_PLATFORM_CONFIG_FILE_LIST})
