#ifndef COMMS_SIM_TOPICIDS_H
#define COMMS_SIM_TOPICIDS_H

#include "comms_sim_topicid_values.h"

/*
 * ICARUS topic-ID block for this app. Each app owns a distinct, non-overlapping
 * block so no two apps can collide on the Software Bus:
 *   adcs_sim    0xC0-0xC3
 *   payload_sim 0xC4-0xC7
 *   comms_sim   0xC8-0xCB
 */
#define COMMS_SIM_MISSION_CMD_TOPICID             COMMS_SIM_MISSION_TIDVAL(CMD)
#define DEFAULT_COMMS_SIM_MISSION_CMD_TOPICID     0xc8

#define COMMS_SIM_MISSION_SEND_HK_TOPICID         COMMS_SIM_MISSION_TIDVAL(SEND_HK)
#define DEFAULT_COMMS_SIM_MISSION_SEND_HK_TOPICID 0xc9

#define COMMS_SIM_MISSION_WAKEUP_TOPICID         COMMS_SIM_MISSION_TIDVAL(WAKEUP)
#define DEFAULT_COMMS_SIM_MISSION_WAKEUP_TOPICID 0xcb

#define COMMS_SIM_MISSION_HK_TLM_TOPICID          COMMS_SIM_MISSION_TIDVAL(HK_TLM)
#define DEFAULT_COMMS_SIM_MISSION_HK_TLM_TOPICID  0xca

#endif
