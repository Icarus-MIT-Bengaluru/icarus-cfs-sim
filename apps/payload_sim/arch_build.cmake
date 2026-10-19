###########################################################
#
# PAYLOAD_SIM platform build setup
#
# Evaluated during the "prepare" stage. Generates the concrete
# config headers from this app's config/ defaults.
#
###########################################################

set(PAYLOAD_SIM_PLATFORM_CONFIG_FILE_LIST
  payload_sim_internal_cfg_values.h
  payload_sim_platform_cfg.h
  payload_sim_perfids.h
  payload_sim_msgids.h
  payload_sim_msgid_values.h
)

generate_configfile_set(${PAYLOAD_SIM_PLATFORM_CONFIG_FILE_LIST})
