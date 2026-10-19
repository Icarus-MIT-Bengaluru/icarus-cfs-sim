#ifndef ADCS_SIM_INTERNAL_CFG_H
#define ADCS_SIM_INTERNAL_CFG_H

#include "adcs_sim_internal_cfg_values.h"

#define ADCS_SIM_PLATFORM_PIPE_DEPTH         ADCS_SIM_PLATFORM_CFGVAL(PIPE_DEPTH)
#define DEFAULT_ADCS_SIM_PLATFORM_PIPE_DEPTH 8

#define ADCS_SIM_PLATFORM_PIPE_NAME         ADCS_SIM_PLATFORM_CFGVAL(PIPE_NAME)
/*
 * Must be at most OS_MAX_API_NAME-1 (19) characters including the null
 * terminator, or CFE_SB_CreatePipe fails with OS_ERR_NAME_TOO_LONG (-13).
 * "PAYLOAD_SIM_CMD_PIPE" was 20 and did exactly that.
 */
#define DEFAULT_ADCS_SIM_PLATFORM_PIPE_NAME "ADCS_SIM_PIPE"

/*
 * This app's declared scheduled rate, in millihertz (10 Hz).
 *
 * It is DOCUMENTATION, not configuration: the real rate is set by this app's
 * PacketRate in controllers/obc/config/mission/tables/sch_lab_table.c. The
 * value is embedded in every wakeup marker so the rate checker can verify the
 * achieved rate against what the app claims, and a mismatch between the two
 * is exactly the defect the Phase 5 gate is meant to catch. Millihertz keeps
 * it an integer -- 0.1 Hz has no clean integer form in Hz.
 */
#define ADCS_SIM_DECLARED_RATE_MHZ 10000

/* This app's own device simulator. It must address no other controller. */
#define ADCS_SIM_PLATFORM_CONTROLLER_HOST         ADCS_SIM_PLATFORM_CFGVAL(CONTROLLER_HOST)
#define DEFAULT_ADCS_SIM_PLATFORM_CONTROLLER_HOST "adcs"

#define ADCS_SIM_PLATFORM_CONTROLLER_PORT         ADCS_SIM_PLATFORM_CFGVAL(CONTROLLER_PORT)
#define DEFAULT_ADCS_SIM_PLATFORM_CONTROLLER_PORT 31001

#endif
