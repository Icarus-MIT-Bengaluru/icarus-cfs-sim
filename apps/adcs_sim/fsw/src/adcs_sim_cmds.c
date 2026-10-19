/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#include "adcs_sim.h"
#include "adcs_sim_cmds.h"
#include "adcs_sim_eventids.h"

CFE_Status_t ADCS_SIM_NoopCmd(const ADCS_SIM_NoopCmd_t *Msg)
{
    ADCS_SIM_Data.CommandCounter++;
    CFE_EVS_SendEvent(ADCS_SIM_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "ADCS_SIM: NOOP command");
    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_ResetCountersCmd(const ADCS_SIM_ResetCountersCmd_t *Msg)
{
    ADCS_SIM_Data.CommandCounter      = 0;
    ADCS_SIM_Data.CommandErrorCounter = 0;
    CFE_EVS_SendEvent(ADCS_SIM_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "ADCS_SIM: counters reset");
    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_SendHelloCmd(const ADCS_SIM_SendHelloCmd_t *Msg)
{
    ADCS_SIM_Data.CommandCounter++;
    ADCS_SIM_Wakeup();
    return CFE_SUCCESS;
}

CFE_Status_t ADCS_SIM_SendHkCmd(const ADCS_SIM_SendHkCmd_t *Msg)
{
    ADCS_SIM_Data.HkTlm.Payload.CommandCounter      = ADCS_SIM_Data.CommandCounter;
    ADCS_SIM_Data.HkTlm.Payload.CommandErrorCounter = ADCS_SIM_Data.CommandErrorCounter;
    ADCS_SIM_Data.HkTlm.Payload.WakeupCounter        = ADCS_SIM_Data.WakeupCounter;
    ADCS_SIM_Data.HkTlm.Payload.UdpLinkReady        = (ADCS_SIM_Data.UdpReady ? 1 : 0);

    CFE_SB_TimeStampMsg(CFE_MSG_PTR(ADCS_SIM_Data.HkTlm.TelemetryHeader));
    CFE_SB_TransmitMsg(CFE_MSG_PTR(ADCS_SIM_Data.HkTlm.TelemetryHeader), true);

    /* TODO: add ADCS housekeeping fields to the payload. */
    return CFE_SUCCESS;
}

/*
 * SIMULATION-ONLY FAULT HOOK (Phase 6). NOT FLIGHT BEHAVIOUR.
 *
 * Stops this app doing its periodic work while leaving it loaded and looping.
 * That is precisely the condition HS's application monitor exists to catch:
 * the app is alive, so it is not an exit, but it is no longer functioning.
 */
CFE_Status_t ADCS_SIM_InjectStallCmd(const ADCS_SIM_InjectStallCmd_t *Msg)
{
    ADCS_SIM_Data.CommandCounter++;
    ADCS_SIM_Data.StallInjected = true;

    CFE_EVS_SendEvent(ADCS_SIM_STALL_INJECTED_INF_EID, CFE_EVS_EventType_CRITICAL,
                      "ADCS_SIM: SIMULATED FAULT -- periodic work stalled by command");

    return CFE_SUCCESS;
}
