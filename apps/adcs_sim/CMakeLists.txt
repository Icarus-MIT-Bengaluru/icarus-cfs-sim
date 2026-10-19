project(CFS_ADCS_SIM C)

set(APP_SRC_FILES
  fsw/src/adcs_sim.c
  fsw/src/adcs_sim_cmds.c
  fsw/src/adcs_sim_dispatch.c
  fsw/src/adcs_sim_udp.c
)

# Create the app module
add_cfe_app(adcs_sim ${APP_SRC_FILES})

target_include_directories(adcs_sim PUBLIC fsw/inc)

# No cFE tables in the Phase 4 skeleton; add_cfe_tables() goes here when the
# app gains configuration tables.

if (ENABLE_UNIT_TESTS)
  add_subdirectory(unit-test)
endif (ENABLE_UNIT_TESTS)
