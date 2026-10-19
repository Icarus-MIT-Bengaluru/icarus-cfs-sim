/*
 * ICARUS Comms subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Comms behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef COMMS_SIM_DISPATCH_H
#define COMMS_SIM_DISPATCH_H

#include "cfe.h"
#include "comms_sim_msg.h"

bool COMMS_SIM_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength);
void COMMS_SIM_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr);
void COMMS_SIM_TaskPipe(const CFE_SB_Buffer_t *SBBufPtr);

#endif /* COMMS_SIM_DISPATCH_H */
