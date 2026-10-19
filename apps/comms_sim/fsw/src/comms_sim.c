/*
 * ICARUS Comms subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Comms behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#include "comms_sim.h"
#include "comms_sim_cmds.h"
#include "comms_sim_dispatch.h"
#include "comms_sim_eventids.h"
#include "comms_sim_udp.h"

COMMS_SIM_Data_t COMMS_SIM_Data;

void COMMS_SIM_Main(void)
{
    CFE_Status_t     status;
    CFE_SB_Buffer_t *SBBufPtr;

    CFE_ES_PerfLogEntry(COMMS_SIM_PERF_ID);

    status = COMMS_SIM_Init();
    if (status != CFE_SUCCESS)
    {
        COMMS_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }

    while (CFE_ES_RunLoop(&COMMS_SIM_Data.RunStatus) == true)
    {
        CFE_ES_PerfLogExit(COMMS_SIM_PERF_ID);

        /*
         * PHASE 5: timing comes from SCH alone. The app pends indefinitely and
         * does periodic work only when its scheduled wakeup arrives, so the
         * observed rate is the scheduler's rate and nothing else. If SCH stops,
         * this app goes quiet -- which is the correct, observable behaviour.
         */
        status = CFE_SB_ReceiveBuffer(&SBBufPtr, COMMS_SIM_Data.CommandPipe,
                                      CFE_SB_PEND_FOREVER);

        CFE_ES_PerfLogEntry(COMMS_SIM_PERF_ID);

        if (status == CFE_SUCCESS)
        {
            COMMS_SIM_TaskPipe(SBBufPtr);
        }
        else
        {
            CFE_EVS_SendEvent(COMMS_SIM_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                              "COMMS_SIM: SB pipe read error, app will exit, RC = 0x%08lX",
                              (unsigned long)status);
            COMMS_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_ERROR;
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
        while (COMMS_SIM_Data.StallInjected)
        {
            OS_TaskDelay(1000);
        }
    }

    CFE_ES_PerfLogExit(COMMS_SIM_PERF_ID);
    CFE_ES_ExitApp(COMMS_SIM_Data.RunStatus);
}

CFE_Status_t COMMS_SIM_Init(void)
{
    CFE_Status_t status;

    memset(&COMMS_SIM_Data, 0, sizeof(COMMS_SIM_Data));
    COMMS_SIM_Data.RunStatus = CFE_ES_RunStatus_APP_RUN;

    status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
    if (status != CFE_SUCCESS)
    {
        CFE_ES_WriteToSysLog("COMMS_SIM: error registering EVS, RC = 0x%08lX\n",
                             (unsigned long)status);
        return status;
    }

    CFE_MSG_Init(CFE_MSG_PTR(COMMS_SIM_Data.HkTlm.TelemetryHeader),
                 CFE_SB_ValueToMsgId(COMMS_SIM_HK_TLM_MID),
                 sizeof(COMMS_SIM_Data.HkTlm));

    status = CFE_SB_CreatePipe(&COMMS_SIM_Data.CommandPipe,
                               COMMS_SIM_PLATFORM_PIPE_DEPTH,
                               COMMS_SIM_PLATFORM_PIPE_NAME);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(COMMS_SIM_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "COMMS_SIM: error creating SB pipe, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(COMMS_SIM_CMD_MID), COMMS_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(COMMS_SIM_SUB_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                          "COMMS_SIM: error subscribing to commands, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(COMMS_SIM_SEND_HK_MID), COMMS_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(COMMS_SIM_SUB_HK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "COMMS_SIM: error subscribing to HK request, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(COMMS_SIM_WAKEUP_MID), COMMS_SIM_Data.CommandPipe);
    if (status != CFE_SUCCESS)
    {
        CFE_EVS_SendEvent(COMMS_SIM_SUB_WAKEUP_ERR_EID, CFE_EVS_EventType_ERROR,
                          "COMMS_SIM: error subscribing to scheduled wakeup, RC = 0x%08lX",
                          (unsigned long)status);
        return status;
    }

    /*
     * Open this app's own UDP route and greet its controller exactly once.
     * A failure here is reported but is NOT fatal: the app must stay alive so
     * Phase 6 can observe a degraded link rather than a vanished app.
     */
    if (COMMS_SIM_UDP_Init() == CFE_SUCCESS)
    {
        COMMS_SIM_Data.UdpReady = true;
        COMMS_SIM_UDP_SendHello();
    }

    /* The startup "hello" this phase is verified by. */
    CFE_EVS_SendEvent(COMMS_SIM_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "COMMS_SIM: hello world from Comms, initialized; controller %s:%u, udp_ready=%u",
                      COMMS_SIM_PLATFORM_CONTROLLER_HOST,
                      (unsigned int)COMMS_SIM_PLATFORM_CONTROLLER_PORT,
                      (unsigned int)COMMS_SIM_Data.UdpReady);

    return CFE_SUCCESS;
}

void COMMS_SIM_Wakeup(void)
{
    OS_time_t now;

    COMMS_SIM_Data.WakeupCounter++;

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
    CFE_EVS_SendEvent(COMMS_SIM_WAKEUP_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "COMMS_SIM: wakeup seq=%lu mono_us=%lld rate_mhz=%lu",
                      (unsigned long)COMMS_SIM_Data.WakeupCounter,
                      (long long)OS_TimeGetTotalMicroseconds(now),
                      (unsigned long)COMMS_SIM_DECLARED_RATE_MHZ);

    /* TODO: Comms periodic work goes here. It now runs at the SCH rate. */
}
