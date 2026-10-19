/*
 * ICARUS Payload subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Payload behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef PAYLOAD_SIM_DISPATCH_H
#define PAYLOAD_SIM_DISPATCH_H

#include "cfe.h"
#include "payload_sim_msg.h"

bool PAYLOAD_SIM_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength);
void PAYLOAD_SIM_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr);
void PAYLOAD_SIM_TaskPipe(const CFE_SB_Buffer_t *SBBufPtr);

#endif /* PAYLOAD_SIM_DISPATCH_H */
