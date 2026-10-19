/*
 * ICARUS Comms subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Comms behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef COMMS_SIM_CMDS_H
#define COMMS_SIM_CMDS_H

#include "cfe.h"
#include "comms_sim_msg.h"

CFE_Status_t COMMS_SIM_NoopCmd(const COMMS_SIM_NoopCmd_t *Msg);
CFE_Status_t COMMS_SIM_ResetCountersCmd(const COMMS_SIM_ResetCountersCmd_t *Msg);
CFE_Status_t COMMS_SIM_SendHelloCmd(const COMMS_SIM_SendHelloCmd_t *Msg);
CFE_Status_t COMMS_SIM_SendHkCmd(const COMMS_SIM_SendHkCmd_t *Msg);

/* Simulation-only fault hook (Phase 6). Not flight behaviour. */
CFE_Status_t COMMS_SIM_InjectStallCmd(const COMMS_SIM_InjectStallCmd_t *Msg);

#endif /* COMMS_SIM_CMDS_H */
