/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef ADCS_SIM_UDP_H
#define ADCS_SIM_UDP_H

#include "cfe.h"

/*
 * This app's private adapter to the ADCS device simulator. It is the ONLY
 * component permitted to address adcs:31001. Cross-app communication uses
 * the cFS Software Bus, never another app's adapter.
 */

/* Opens the socket and resolves the controller. Non-fatal on failure. */
CFE_Status_t ADCS_SIM_UDP_Init(void);

/* Sends exactly one fixed hello datagram. Phase 4 integration proof. */
CFE_Status_t ADCS_SIM_UDP_SendHello(void);

/* TODO: generic send. Body is a stub. */
CFE_Status_t ADCS_SIM_UDP_Send(const void *Buffer, size_t Size);

/* TODO: receive with bounded timeout. Body is a stub. */
CFE_Status_t ADCS_SIM_UDP_Receive(void *Buffer, size_t Size, size_t *Received, int32 TimeoutMs);

#endif /* ADCS_SIM_UDP_H */
