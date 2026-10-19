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
#include "payload_sim_dispatch.h"
#include "payload_sim_eventids.h"
#include "payload_sim_udp.h"

PAYLOAD_SIM_Data_t PAYLOAD_SIM_Data;

void PAYLOAD_SIM_Main(void)
{
    CFE_Status_t     status;
    CFE_SB_Buffer_t *SBBufPtr;

    CFE_ES_PerfLogEntry(PAYLOAD_SIM_PERF_ID);

    status = PAYLOAD_SIM_Init();
    if (status != CFE_SUCCESS)
    {
        PAYLOAD_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }

    while (CFE_ES_RunLoop(&PAYLOAD_SIM_Data.RunStatus) == true)
    {
        CFE_ES_PerfLogExit(PAYLOAD_SIM_PERF_ID);

        /*
         * PHASE 5: timing comes from SCH alone. The app pends indefinitely and
         * does periodic work only when its scheduled wakeup arrives, so the
         * observed rate is the scheduler's rate and nothing else. If SCH stops,
         * this app goes quiet -- which is the correct, observable behaviour.
         */
        status = CFE_SB_ReceiveBuffer(&SBBufPtr, PAYLOAD_SIM_Data.CommandPipe,
                                      CFE_SB_PEND_FOREVER);

        CFE_ES_PerfLogEntry(PAYLOAD_SIM_PERF_ID);

        if (status == CFE_SUCCESS)
        {
            PAYLOAD_SIM_TaskPipe(SBBufPtr);
        }
        else
        {
            CFE_EVS_SendEvent(PAYLOAD_SIM_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                              "PAYLOAD_SIM: SB pipe read error, app will exit, RC = 0x%08lX",
                              (unsigned long)status);
            PAYLOAD_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_ERROR;
        }

        /*
         * SIMULATION-ONLY FAULT HOOK (Phase 6). NOT FLIGHT BEHAVIOUR.
         *
         * Blocks inside the loop body so CFE_ES_RunLoop is never re-entered.
         * CFE_ES_RunLoop is what calls CFE_ES_IncrementTaskCounter, so the ES
         * execution counter freezes while the task stays alive and registered
         * -- exactly the "app exists but is not executing" condition that HS
         * application monitoring detects. Returning early from the wakeup
         * handler instead would leave the counter advancing and HS would never
         * notice, which would make the Phase 6 evidence meaningless.
         */
        while (PAYLOAD_SIM_Data.StallInjected)
        {
            OS_TaskDelay(1000);
        }
    }

    CFE_ES_PerfLogExit(PAYLOAD_SIM_PERF_ID);
    CFE_ES_ExitApp(PAYLOAD_SIM_Data.RunStatus);
}

CFE_Status_t PAYLOAD_SIM_Init(void)
{
    CFE_Status_t status;

    memset(&PAYLOAD_SIM_Data, 0, sizeof(PAYLOAD_SIM_Data));
    PAYLOAD_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_RUN;

    status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
    if (status != CFE_SUCCESS)
    {
        CFE_ES_WriteToSysLog("PAYLOAD_SIM: error registering EVS, RC = 0x%08lX\n",
                             (unsigned long)status);
        return status;
    }

    CFE_MSG_Init(CFE_MSG_PTR(PAYLOAD_SIM_Data.HkTlm.TelemetryHeader),
                 CFE_SB_ValueToMsgId(PAYLOAD_SIM_HK_TLM_MID),
                 sizeof(PAYLOAD_SIM_Data.HkTlm));

    status = CFE_SB_CreatePipe(&PAYLOAD_SIM_Data.CommandPipe,
                               PAYLOAD_SIM_PLATFORM_PIPE_DEPTH,
                               PAYLOAD_SIM_PLATFORM_PIPE_NAME);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(PAYLOAD_SIM_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PAYLOAD_SIM: error creating SB pipe, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(PAYLOAD_SIM_CMD_MID), PAYLOAD_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(PAYLOAD_SIM_SUB_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PAYLOAD_SIM: error subscribing to commands, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(PAYLOAD_SIM_SEND_HK_MID), PAYLOAD_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(PAYLOAD_SIM_SUB_HK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PAYLOAD_SIM: error subscribing to HK request, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(PAYLOAD_SIM_WAKEUP_MID), PAYLOAD_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(PAYLOAD_SIM_SUB_WAKEUP_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PAYLOAD_SIM: error subscribing to scheduled wakeup, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    /*
     * Open this app's own UDP route and greet its controller exactly once.
     * A failure here is reported but is NOT fatal: the app must stay alive so
     * Phase 6 can observe a degraded link rather than a vanished app.
     */
    if (PAYLOAD_SIM_UDP_Init() == CFE_SUCCESS)
    {
        PAYLOAD_SIM_Data.UdpReady = true;
        PAYLOAD_SIM_UDP_SendHello();
    }

    /* The startup "hello" this phase is verified by. */
    CFE_EVS_SendEvent(PAYLOAD_SIM_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "PAYLOAD_SIM: hello world from Payload, initialized; controller %s:%u, udp_ready=%u",
                      PAYLOAD_SIM_PLATFORM_CONTROLLER_HOST,
                      (unsigned int)PAYLOAD_SIM_PLATFORM_CONTROLLER_PORT,
                      (unsigned int)PAYLOAD_SIM_Data.UdpReady);

    return CFE_SUCCESS;
}

void PAYLOAD_SIM_Wakeup(void)
{
    OS_time_t now;

    PAYLOAD_SIM_Data.WakeupCounter++;

    /*
     * Timing source: CFE_PSP_GetTime, which on this target is
     * clock_gettime(CLOCK_MONOTONIC). It is read as ONE int64 microsecond
     * count via OS_TimeGetTotalMicroseconds, so the value cannot tear.
     *
     * Deliberately NOT CFE_TIME_GetMET(): its CFE_TIME_SysTime_t splits into
     * separate Seconds and Subseconds fields, and in practice the subseconds
     * were observed wrapping without the seconds field carrying, which
     * produced negative intervals. A single monotonic integer removes that
     * whole class of bug. Also not CFE_TIME_GetTime(), which is the
     * ground-commandable TAI/UTC clock and can jump.
     *
     * The timestamp is embedded in the marker because OSAL's console is
     * asynchronous: log lines are delivered in bursts, so the time a line is
     * written bears no relation to when the event occurred.
     */
    CFE_PSP_GetTime(&now);

    /*
     * Exactly ONE event per wakeup. CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC is 15
     * per app; at 10 Hz this app already uses 10, so a second event here would
     * trip EVS squelching and drop markers.
     */
    CFE_EVS_SendEvent(PAYLOAD_SIM_WAKEUP_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "PAYLOAD_SIM: wakeup seq=%lu mono_us=%lld rate_mhz=%lu",
                      (unsigned long)PAYLOAD_SIM_Data.WakeupCounter,
                      (long long)OS_TimeGetTotalMicroseconds(now),
                      (unsigned long)PAYLOAD_SIM_DECLARED_RATE_MHZ);

    /* TODO: Payload periodic work goes here. It now runs at the SCH rate. */
}
