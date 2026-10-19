##########################################################################
#
# ICARUS cFE startup script generator
#
# Replaces the sample generator. Writes cfe_es_startup.scr with the ICARUS
# applications and the retained stock apps only -- notably without SBN.
#
##########################################################################

function (generate_cfs_startup_script CFS_INSTALL_DIR)
    set (STARTUP_FILE "$ENV{DESTDIR}${CMAKE_INSTALL_PREFIX}/${CFS_INSTALL_DIR}/cfe_es_startup.scr")

    # Core library and the scheduler/command/telemetry path.
    file (WRITE ${STARTUP_FILE}
        "CFE_LIB, cfe_assert,  CFE_Assert_LibInit, ASSERT_LIB,    0,   0,     0x0, 0;\n"
        "CFE_APP, sch_lab,     SCH_LAB_AppMain,    SCH_LAB,      35,   32768, 0x0, 0;\n"
        "CFE_APP, ci_lab,      CI_LAB_AppMain,     CI_LAB,       40,   32768, 0x0, 0;\n"
        "CFE_APP, to_lab,      TO_LAB_AppMain,     TO_LAB,       45,   32768, 0x0, 0;\n"
    )

    # ICARUS subsystem applications. Each is loaded as its own module with its
    # own entry point, priority and stack -- never combined.
    file (APPEND ${STARTUP_FILE}
        "CFE_APP, adcs_sim,    ADCS_SIM_Main,      ADCS_SIM,     50,   32768, 0x0, 0;\n"
        "CFE_APP, payload_sim, PAYLOAD_SIM_Main,   PAYLOAD_SIM,  51,   32768, 0x0, 0;\n"
        "CFE_APP, comms_sim,   COMMS_SIM_Main,     COMMS_SIM,    52,   32768, 0x0, 0;\n"
    )

    # Health and Safety last, so the apps it monitors are already running.
    set(CFS_APP_STARTUP_ORDER hs)
    foreach(APP ${CFS_APP_STARTUP_ORDER})
        list(FIND ARGN ${APP} SHOULD_START)
        if (SHOULD_START GREATER -1)
            string(TOUPPER "${APP}" APP_UPPER)
            file (APPEND ${STARTUP_FILE}
                "CFE_APP, ${APP},  ${APP_UPPER}_AppMain, ${APP_UPPER}, 70,  131072, 0x0, 0;\n"
            )
        endif()
    endforeach()

endfunction(generate_cfs_startup_script)
