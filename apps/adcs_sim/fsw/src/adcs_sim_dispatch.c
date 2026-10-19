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
#include "adcs_sim_dispatch.h"
#include "adcs_sim_eventids.h"

bool ADCS_SIM_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength)
{
    bool              result       = true;
    size_t            ActualLength = 0;
    CFE_SB_MsgId_t    MsgId        = CFE_SB_INVALID_MSG_ID;
    CFE_MSG_FcnCode_t FcnCode      = 0;

    CFE_MSG_GetSize(MsgPtr, &ActualLength);

    if (ExpectedLength != ActualLength)
    {
        CFE_MSG_GetMsgId(MsgPtr, &MsgId);
        CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);

        CFE_EVS_SendEvent(ADCS_SIM_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ADCS_SIM: invalid msg length: ID = 0x%X, CC = %u, Len = %u, Expected = %u",
                          (unsigned int)CFE_SB_MsgIdToValue(MsgId), (unsigned int)FcnCode,
                          (unsigned int)ActualLength, (unsigned int)ExpectedLength);
        result = false;
        ADCS_SIM_Data.CommandErrorCounter++;
    }

    return result;
}

void ADCS_SIM_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr)
{
    CFE_MSG_FcnCode_t CommandCode = 0;

    CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &CommandCode);

    switch (CommandCode)
    {
        case ADCS_SIM_NOOP_CC:
            if (ADCS_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(ADCS_SIM_NoopCmd_t)))
            {
                ADCS_SIM_NoopCmd((const ADCS_SIM_NoopCmd_t *)SBBufPtr);
            }
            break;

        case ADCS_SIM_RESET_COUNTERS_CC:
            if (ADCS_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(ADCS_SIM_ResetCountersCmd_t)))
            {
                ADCS_SIM_ResetCountersCmd((const ADCS_SIM_ResetCountersCmd_t *)SBBufPtr);
            }
            break;

        case ADCS_SIM_SEND_HELLO_CC:
            if (ADCS_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(ADCS_SIM_SendHelloCmd_t)))
            {
                ADCS_SIM_SendHelloCmd((const ADCS_SIM_SendHelloCmd_t *)SBBufPtr);
            }
            break;

        case ADCS_SIM_INJECT_STALL_CC:
            if (ADCS_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(ADCS_SIM_InjectStallCmd_t)))
            {
                ADCS_SIM_InjectStallCmd((const ADCS_SIM_InjectStallCmd_t *)SBBufPtr);
            }
            break;

        /* TODO: add ADCS command codes here. */

        default:
            CFE_EVS_SendEvent(ADCS_SIM_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                              "ADCS_SIM: invalid command code: CC = %d", CommandCode);
            ADCS_SIM_Data.CommandErrorCounter++;
            break;
    }
}

void ADCS_SIM_TaskPipe(const CFE_SB_Buffer_t *SBBufPtr)
{
    CFE_SB_MsgId_t MsgId = CFE_SB_INVALID_MSG_ID;

    CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MsgId);

    switch (CFE_SB_MsgIdToValue(MsgId))
    {
        case ADCS_SIM_CMD_MID:
            ADCS_SIM_ProcessGroundCommand(SBBufPtr);
            break;

        case ADCS_SIM_SEND_HK_MID:
            ADCS_SIM_SendHkCmd((const ADCS_SIM_SendHkCmd_t *)SBBufPtr);
            break;

        case ADCS_SIM_WAKEUP_MID:
            if (ADCS_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(ADCS_SIM_WakeupCmd_t)))
            {
                ADCS_SIM_Wakeup();
            }
            break;

        default:
            CFE_EVS_SendEvent(ADCS_SIM_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                              "ADCS_SIM: invalid command packet, MID = 0x%x",
                              (unsigned int)CFE_SB_MsgIdToValue(MsgId));
            ADCS_SIM_Data.CommandErrorCounter++;
            break;
    }
}
