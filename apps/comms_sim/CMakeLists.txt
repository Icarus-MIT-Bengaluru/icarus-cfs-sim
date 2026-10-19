project(CFS_COMMS_SIM C)

set(APP_SRC_FILES
  fsw/src/comms_sim.c
  fsw/src/comms_sim_cmds.c
  fsw/src/comms_sim_dispatch.c
  fsw/src/comms_sim_udp.c
)

# Create the app module
add_cfe_app(comms_sim ${APP_SRC_FILES})

target_include_directories(comms_sim PUBLIC fsw/inc)

# No cFE tables in the Phase 4 skeleton; add_cfe_tables() goes here when the
# app gains configuration tables.

if (ENABLE_UNIT_TESTS)
  add_subdirectory(unit-test)
endif (ENABLE_UNIT_TESTS)
