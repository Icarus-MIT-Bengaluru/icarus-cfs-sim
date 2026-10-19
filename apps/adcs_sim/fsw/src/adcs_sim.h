/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef ADCS_SIM_H
#define ADCS_SIM_H

#include "cfe.h"
#include "osapi.h"
#include "cfe_psp.h"
#include "adcs_sim_mission_cfg.h"
#include "adcs_sim_platform_cfg.h"
#include "adcs_sim_perfids.h"
#include "adcs_sim_msgids.h"
#include "adcs_sim_msg.h"

typedef struct
{
    uint8  CommandCounter;
    uint8  CommandErrorCounter;
    uint32 WakeupCounter;

    ADCS_SIM_HkTlm_t HkTlm;

    uint32          RunStatus;
    CFE_SB_PipeId_t CommandPipe;

    /*
     * SIMULATION-ONLY fault state (Phase 6). Not flight behaviour. When set,
     * the app keeps running and keeps consuming its scheduled wakeups but
     * performs no periodic work, so its ES execution counter still advances
     * while its observable output stops.
     */
    bool StallInjected;

    /* This app's own UDP route. No other app may touch these. */
    osal_id_t     UdpSocket;
    OS_SockAddr_t UdpPeer;
    bool          UdpReady;
} ADCS_SIM_Data_t;

extern ADCS_SIM_Data_t ADCS_SIM_Data;

void         ADCS_SIM_Main(void);
CFE_Status_t ADCS_SIM_Init(void);
void         ADCS_SIM_Wakeup(void);

#endif /* ADCS_SIM_H */
