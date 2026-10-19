#ifndef PAYLOAD_SIM_TOPICIDS_H
#define PAYLOAD_SIM_TOPICIDS_H

#include "payload_sim_topicid_values.h"

/*
 * ICARUS topic-ID block for this app. Each app owns a distinct, non-overlapping
 * block so no two apps can collide on the Software Bus:
 *   adcs_sim    0xC0-0xC3
 *   payload_sim 0xC4-0xC7
 *   comms_sim   0xC8-0xCB
 */
#define PAYLOAD_SIM_MISSION_CMD_TOPICID             PAYLOAD_SIM_MISSION_TIDVAL(CMD)
#define DEFAULT_PAYLOAD_SIM_MISSION_CMD_TOPICID     0xc4

#define PAYLOAD_SIM_MISSION_SEND_HK_TOPICID         PAYLOAD_SIM_MISSION_TIDVAL(SEND_HK)
#define DEFAULT_PAYLOAD_SIM_MISSION_SEND_HK_TOPICID 0xc5

#define PAYLOAD_SIM_MISSION_WAKEUP_TOPICID         PAYLOAD_SIM_MISSION_TIDVAL(WAKEUP)
#define DEFAULT_PAYLOAD_SIM_MISSION_WAKEUP_TOPICID 0xc7

#define PAYLOAD_SIM_MISSION_HK_TLM_TOPICID          PAYLOAD_SIM_MISSION_TIDVAL(HK_TLM)
#define DEFAULT_PAYLOAD_SIM_MISSION_HK_TLM_TOPICID  0xc6

#endif
