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

bool PAYLOAD_SIM_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength)
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

        CFE_EVS_SendEvent(PAYLOAD_SIM_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                          "PAYLOAD_SIM: invalid msg length: ID = 0x%X, CC = %u, Len = %u, Expected = %u",
                          (unsigned int)CFE_SB_MsgIdToValue(MsgId), (unsigned int)FcnCode,
                          (unsigned int)ActualLength, (unsigned int)ExpectedLength);
        result = false;
        PAYLOAD_SIM_Data.CommandErrorCounter++;
    }

    return result;
}

void PAYLOAD_SIM_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr)
{
    CFE_MSG_FcnCode_t CommandCode = 0;

    CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &CommandCode);

    switch (CommandCode)
    {
        case PAYLOAD_SIM_NOOP_CC:
            if (PAYLOAD_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(PAYLOAD_SIM_NoopCmd_t)))
            {
                PAYLOAD_SIM_NoopCmd((const PAYLOAD_SIM_NoopCmd_t *)SBBufPtr);
            }
            break;

        case PAYLOAD_SIM_RESET_COUNTERS_CC:
            if (PAYLOAD_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(PAYLOAD_SIM_ResetCountersCmd_t)))
            {
                PAYLOAD_SIM_ResetCountersCmd((const PAYLOAD_SIM_ResetCountersCmd_t *)SBBufPtr);
            }
            break;

        case PAYLOAD_SIM_SEND_HELLO_CC:
            if (PAYLOAD_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(PAYLOAD_SIM_SendHelloCmd_t)))
            {
                PAYLOAD_SIM_SendHelloCmd((const PAYLOAD_SIM_SendHelloCmd_t *)SBBufPtr);
            }
            break;

        case PAYLOAD_SIM_INJECT_STALL_CC:
            if (PAYLOAD_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(PAYLOAD_SIM_InjectStallCmd_t)))
            {
                PAYLOAD_SIM_InjectStallCmd((const PAYLOAD_SIM_InjectStallCmd_t *)SBBufPtr);
            }
            break;

        /* TODO: add Payload command codes here. */

        default:
            CFE_EVS_SendEvent(PAYLOAD_SIM_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                              "PAYLOAD_SIM: invalid command code: CC = %d", CommandCode);
            PAYLOAD_SIM_Data.CommandErrorCounter++;
            break;
    }
}

void PAYLOAD_SIM_TaskPipe(const CFE_SB_Buffer_t *SBBufPtr)
{
    CFE_SB_MsgId_t MsgId = CFE_SB_INVALID_MSG_ID;

    CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MsgId);

    switch (CFE_SB_MsgIdToValue(MsgId))
    {
        case PAYLOAD_SIM_CMD_MID:
            PAYLOAD_SIM_ProcessGroundCommand(SBBufPtr);
            break;

        case PAYLOAD_SIM_SEND_HK_MID:
            PAYLOAD_SIM_SendHkCmd((const PAYLOAD_SIM_SendHkCmd_t *)SBBufPtr);
            break;

        case PAYLOAD_SIM_WAKEUP_MID:
            if (PAYLOAD_SIM_VerifyCmdLength(&SBBufPtr->Msg, sizeof(PAYLOAD_SIM_WakeupCmd_t)))
            {
                PAYLOAD_SIM_Wakeup();
            }
            break;

        default:
            CFE_EVS_SendEvent(PAYLOAD_SIM_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                              "PAYLOAD_SIM: invalid command packet, MID = 0x%x",
                              (unsigned int)CFE_SB_MsgIdToValue(MsgId));
            PAYLOAD_SIM_Data.CommandErrorCounter++;
            break;
    }
}
