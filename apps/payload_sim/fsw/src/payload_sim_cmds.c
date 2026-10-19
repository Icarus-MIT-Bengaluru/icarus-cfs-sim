/*
 * ICARUS Payload subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Payload behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#include "payload_sim.h"
#include "payload_sim_cmds.h"
#include "payload_sim_eventids.h"

CFE_Status_t PAYLOAD_SIM_NoopCmd(const PAYLOAD_SIM_NoopCmd_t *Msg)
{
    PAYLOAD_SIM_Data.CommandCounter++;
    CFE_EVS_SendEvent(PAYLOAD_SIM_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "PAYLOAD_SIM: NOOP command");
    return CFE_SUCCESS;
}

CFE_Status_t PAYLOAD_SIM_ResetCountersCmd(const PAYLOAD_SIM_ResetCountersCmd_t *Msg)
{
    PAYLOAD_SIM_Data.CommandCounter      = 0;
    PAYLOAD_SIM_Data.CommandErrorCounter = 0;
    CFE_EVS_SendEvent(PAYLOAD_SIM_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "PAYLOAD_SIM: counters reset");
    return CFE_SUCCESS;
}

CFE_Status_t PAYLOAD_SIM_SendHelloCmd(const PAYLOAD_SIM_SendHelloCmd_t *Msg)
{
    PAYLOAD_SIM_Data.CommandCounter++;
    PAYLOAD_SIM_Wakeup();
    return CFE_SUCCESS;
}

CFE_Status_t PAYLOAD_SIM_SendHkCmd(const PAYLOAD_SIM_SendHkCmd_t *Msg)
{
    PAYLOAD_SIM_Data.HkTlm.Payload.CommandCounter      = PAYLOAD_SIM_Data.CommandCounter;
    PAYLOAD_SIM_Data.HkTlm.Payload.CommandErrorCounter = PAYLOAD_SIM_Data.CommandErrorCounter;
    PAYLOAD_SIM_Data.HkTlm.Payload.WakeupCounter        = PAYLOAD_SIM_Data.WakeupCounter;
    PAYLOAD_SIM_Data.HkTlm.Payload.UdpLinkReady        = (PAYLOAD_SIM_Data.UdpReady ? 1 : 0);

    CFE_SB_TimeStampMsg(CFE_MSG_PTR(PAYLOAD_SIM_Data.HkTlm.TelemetryHeader));
    CFE_SB_TransmitMsg(CFE_MSG_PTR(PAYLOAD_SIM_Data.HkTlm.TelemetryHeader), true);

    /* TODO: add Payload housekeeping fields to the payload. */
    return CFE_SUCCESS;
}

/*
 * SIMULATION-ONLY FAULT HOOK (Phase 6). NOT FLIGHT BEHAVIOUR.
 *
 * Stops this app doing its periodic work while leaving it loaded and looping.
 * That is precisely the condition HS's application monitor exists to catch:
 * the app is alive, so it is not an exit, but it is no longer functioning.
 */
CFE_Status_t PAYLOAD_SIM_InjectStallCmd(const PAYLOAD_SIM_InjectStallCmd_t *Msg)
{
    PAYLOAD_SIM_Data.CommandCounter++;
    PAYLOAD_SIM_Data.StallInjected = true;

    CFE_EVS_SendEvent(PAYLOAD_SIM_STALL_INJECTED_INF_EID, CFE_EVS_EventType_CRITICAL,
                      "PAYLOAD_SIM: SIMULATED FAULT -- periodic work stalled by command");

    return CFE_SUCCESS;
}
