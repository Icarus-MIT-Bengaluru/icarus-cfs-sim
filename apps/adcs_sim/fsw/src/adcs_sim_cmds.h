/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef ADCS_SIM_CMDS_H
#define ADCS_SIM_CMDS_H

#include "cfe.h"
#include "adcs_sim_msg.h"

CFE_Status_t ADCS_SIM_NoopCmd(const ADCS_SIM_NoopCmd_t *Msg);
CFE_Status_t ADCS_SIM_ResetCountersCmd(const ADCS_SIM_ResetCountersCmd_t *Msg);
CFE_Status_t ADCS_SIM_SendHelloCmd(const ADCS_SIM_SendHelloCmd_t *Msg);
CFE_Status_t ADCS_SIM_SendHkCmd(const ADCS_SIM_SendHkCmd_t *Msg);

/* Simulation-only fault hook (Phase 6). Not flight behaviour. */
CFE_Status_t ADCS_SIM_InjectStallCmd(const ADCS_SIM_InjectStallCmd_t *Msg);

#endif /* ADCS_SIM_CMDS_H */
