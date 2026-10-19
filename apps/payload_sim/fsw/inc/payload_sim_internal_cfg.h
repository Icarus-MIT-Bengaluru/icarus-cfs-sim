#ifndef PAYLOAD_SIM_INTERNAL_CFG_H
#define PAYLOAD_SIM_INTERNAL_CFG_H

#include "payload_sim_internal_cfg_values.h"

#define PAYLOAD_SIM_PLATFORM_PIPE_DEPTH         PAYLOAD_SIM_PLATFORM_CFGVAL(PIPE_DEPTH)
#define DEFAULT_PAYLOAD_SIM_PLATFORM_PIPE_DEPTH 8

#define PAYLOAD_SIM_PLATFORM_PIPE_NAME         PAYLOAD_SIM_PLATFORM_CFGVAL(PIPE_NAME)
/*
 * Must be at most OS_MAX_API_NAME-1 (19) characters including the null
 * terminator, or CFE_SB_CreatePipe fails with OS_ERR_NAME_TOO_LONG (-13).
 * "PAYLOAD_SIM_CMD_PIPE" was 20 and did exactly that.
 */
#define DEFAULT_PAYLOAD_SIM_PLATFORM_PIPE_NAME "PAYLOAD_SIM_PIPE"

/*
 * This app's declared scheduled rate, in millihertz (1 Hz).
 *
 * It is DOCUMENTATION, not configuration: the real rate is set by this app's
 * PacketRate in controllers/obc/config/mission/tables/sch_lab_table.c. The
 * value is embedded in every wakeup marker so the rate checker can verify the
 * achieved rate against what the app claims, and a mismatch between the two
 * is exactly the defect the Phase 5 gate is meant to catch. Millihertz keeps
 * it an integer -- 0.1 Hz has no clean integer form in Hz.
 */
#define PAYLOAD_SIM_DECLARED_RATE_MHZ 1000

/* This app's own device simulator. It must address no other controller. */
#define PAYLOAD_SIM_PLATFORM_CONTROLLER_HOST         PAYLOAD_SIM_PLATFORM_CFGVAL(CONTROLLER_HOST)
#define DEFAULT_PAYLOAD_SIM_PLATFORM_CONTROLLER_HOST "payload"

#define PAYLOAD_SIM_PLATFORM_CONTROLLER_PORT         PAYLOAD_SIM_PLATFORM_CFGVAL(CONTROLLER_PORT)
#define DEFAULT_PAYLOAD_SIM_PLATFORM_CONTROLLER_PORT 31002

#endif
