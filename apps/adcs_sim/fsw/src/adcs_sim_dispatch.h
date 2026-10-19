/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef ADCS_SIM_DISPATCH_H
#define ADCS_SIM_DISPATCH_H

#include "cfe.h"
#include "adcs_sim_msg.h"

bool ADCS_SIM_VerifyCmdLength(const CFE_MSG_Message_t *MsgPtr, size_t ExpectedLength);
void ADCS_SIM_ProcessGroundCommand(const CFE_SB_Buffer_t *SBBufPtr);
void ADCS_SIM_TaskPipe(const CFE_SB_Buffer_t *SBBufPtr);

#endif /* ADCS_SIM_DISPATCH_H */
