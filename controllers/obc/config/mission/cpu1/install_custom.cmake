##########################################################################
#
# ICARUS cpu1 install customization
#
# Replaces the sample version, which referenced eleven applications that
# ICARUS does not build. Every target named here must exist, or the build
# fails at configure time.
#
##########################################################################

# For native builds, ship the container start wrapper (inherited file).
if (${SIMULATION} MATCHES "^native")
    install(PROGRAMS ${CMAKE_CURRENT_LIST_DIR}/container-start DESTINATION cpu1)
endif()

# Include paths needed to compile the sch_lab and to_lab table sources.
# Only retained and ICARUS-owned targets appear here.
set(APP_INCLUDE_TABLE_LIST
    $<TARGET_PROPERTY:ci_lab,INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:to_lab,INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:hs,INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:adcs_sim,INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:payload_sim,INCLUDE_DIRECTORIES>
    $<TARGET_PROPERTY:comms_sim,INCLUDE_DIRECTORIES>
)

target_include_directories(to_lab.table INTERFACE ${APP_INCLUDE_TABLE_LIST})
target_include_directories(sch_lab.table INTERFACE ${APP_INCLUDE_TABLE_LIST})

# Generate the ICARUS startup script.
install(SCRIPT ${MISSION_DEFS}/generate_startup.cmake)
install(CODE "generate_cfs_startup_script(\"${TGTNAME}/${INSTALL_SUBDIR}\" ${${TGTNAME}_APPLIST})")
