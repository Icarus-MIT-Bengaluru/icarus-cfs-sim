#ifndef DEFAULT_ADCS_SIM_MSGDEFS_H
#define DEFAULT_ADCS_SIM_MSGDEFS_H

#include "common_types.h"
#include "adcs_sim_fcncodes.h"

/*
 * Housekeeping payload. Phase 4 reports only lifecycle counters; add
 * ADCS-specific fields here.
 */
typedef struct ADCS_SIM_HkTlm_Payload
{
    uint8  CommandCounter;
    uint8  CommandErrorCounter;
    uint32 WakeupCounter;  /**< scheduled wakeups handled since startup */
    uint8  UdpLinkReady;   /**< 1 once this app has opened its own UDP route */
} ADCS_SIM_HkTlm_Payload_t;

#endif
