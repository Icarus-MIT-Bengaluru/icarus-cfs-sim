/*
 * ICARUS Payload subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Payload behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef PAYLOAD_SIM_CMDS_H
#define PAYLOAD_SIM_CMDS_H

#include "cfe.h"
#include "payload_sim_msg.h"

CFE_Status_t PAYLOAD_SIM_NoopCmd(const PAYLOAD_SIM_NoopCmd_t *Msg);
CFE_Status_t PAYLOAD_SIM_ResetCountersCmd(const PAYLOAD_SIM_ResetCountersCmd_t *Msg);
CFE_Status_t PAYLOAD_SIM_SendHelloCmd(const PAYLOAD_SIM_SendHelloCmd_t *Msg);
CFE_Status_t PAYLOAD_SIM_SendHkCmd(const PAYLOAD_SIM_SendHkCmd_t *Msg);

/* Simulation-only fault hook (Phase 6). Not flight behaviour. */
CFE_Status_t PAYLOAD_SIM_InjectStallCmd(const PAYLOAD_SIM_InjectStallCmd_t *Msg);

#endif /* PAYLOAD_SIM_CMDS_H */
