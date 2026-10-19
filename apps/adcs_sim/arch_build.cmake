###########################################################
#
# ADCS_SIM platform build setup
#
# Evaluated during the "prepare" stage. Generates the concrete
# config headers from this app's config/ defaults.
#
###########################################################

set(ADCS_SIM_PLATFORM_CONFIG_FILE_LIST
  adcs_sim_internal_cfg_values.h
  adcs_sim_platform_cfg.h
  adcs_sim_perfids.h
  adcs_sim_msgids.h
  adcs_sim_msgid_values.h
)

generate_configfile_set(${ADCS_SIM_PLATFORM_CONFIG_FILE_LIST})
