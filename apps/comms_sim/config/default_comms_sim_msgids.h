#ifndef DEFAULT_COMMS_SIM_MSGIDS_H
#define DEFAULT_COMMS_SIM_MSGIDS_H

#include "cfe_core_api_base_msgids.h"
#include "comms_sim_msgid_values.h"

#define COMMS_SIM_CMD_MID     COMMS_SIM_CMD_PLATFORM_MIDVAL(CMD)
#define COMMS_SIM_SEND_HK_MID COMMS_SIM_CMD_PLATFORM_MIDVAL(SEND_HK)
/*
 * WAKEUP is a COMMAND mid on purpose. sch_lab sizes a scheduled packet as
 * sizeof(CFE_MSG_CommandHeader_t) + PayloadLength and CFE_MSG_SetFcnCode
 * silently fails on a telemetry mid, so a TLM wakeup would be malformed.
 */
#define COMMS_SIM_WAKEUP_MID  COMMS_SIM_CMD_PLATFORM_MIDVAL(WAKEUP)
#define COMMS_SIM_HK_TLM_MID  COMMS_SIM_TLM_PLATFORM_MIDVAL(HK_TLM)

#endif
