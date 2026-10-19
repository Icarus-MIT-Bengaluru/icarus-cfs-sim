##################################################################
#
# PAYLOAD_SIM coverage unit test recipe
#
# PHASE 4: the harness is wired so the cFS build discovers this test and
# `make native_std.test` runs it. The test body is a placeholder --
# replace it as logic lands.
#
# All of the app's units are compiled into one test object (SUBJECT_SOURCES),
# so no per-unit stub library is needed. When the tests grow into real
# per-unit coverage, split them up and add add_cfe_coverage_stubs() the way
# cfs/apps/sample_app/unit-test does.
#
##################################################################

include_directories(../fsw/src)

add_cfe_coverage_test(payload_sim
  UNIT_NAME        "app"
  TESTCASE_SOURCES "coveragetest/coveragetest_payload_sim.c"
  SUBJECT_SOURCES  ../fsw/src/payload_sim.c
                   ../fsw/src/payload_sim_cmds.c
                   ../fsw/src/payload_sim_dispatch.c
                   ../fsw/src/payload_sim_udp.c
)
