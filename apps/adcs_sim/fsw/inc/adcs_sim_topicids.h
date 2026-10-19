#ifndef ADCS_SIM_TOPICIDS_H
#define ADCS_SIM_TOPICIDS_H

#include "adcs_sim_topicid_values.h"

/*
 * ICARUS topic-ID block for this app. Each app owns a distinct, non-overlapping
 * block so no two apps can collide on the Software Bus:
 *   adcs_sim    0xC0-0xC3
 *   payload_sim 0xC4-0xC7
 *   comms_sim   0xC8-0xCB
 */
#define ADCS_SIM_MISSION_CMD_TOPICID             ADCS_SIM_MISSION_TIDVAL(CMD)
#define DEFAULT_ADCS_SIM_MISSION_CMD_TOPICID     0xc0

#define ADCS_SIM_MISSION_SEND_HK_TOPICID         ADCS_SIM_MISSION_TIDVAL(SEND_HK)
#define DEFAULT_ADCS_SIM_MISSION_SEND_HK_TOPICID 0xc1

#define ADCS_SIM_MISSION_WAKEUP_TOPICID         ADCS_SIM_MISSION_TIDVAL(WAKEUP)
#define DEFAULT_ADCS_SIM_MISSION_WAKEUP_TOPICID 0xc3

#define ADCS_SIM_MISSION_HK_TLM_TOPICID          ADCS_SIM_MISSION_TIDVAL(HK_TLM)
#define DEFAULT_ADCS_SIM_MISSION_HK_TLM_TOPICID  0xc2

#endif
