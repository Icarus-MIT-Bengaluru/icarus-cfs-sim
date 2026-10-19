/*
 * ICARUS Comms subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement Comms behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#ifndef COMMS_SIM_UDP_H
#define COMMS_SIM_UDP_H

#include "cfe.h"

/*
 * This app's private adapter to the Comms device simulator. It is the ONLY
 * component permitted to address comms:31003. Cross-app communication uses
 * the cFS Software Bus, never another app's adapter.
 */

/* Opens the socket and resolves the controller. Non-fatal on failure. */
CFE_Status_t COMMS_SIM_UDP_Init(void);

/* Sends exactly one fixed hello datagram. Phase 4 integration proof. */
CFE_Status_t COMMS_SIM_UDP_SendHello(void);

/* TODO: generic send. Body is a stub. */
CFE_Status_t COMMS_SIM_UDP_Send(const void *Buffer, size_t Size);

/* TODO: receive with bounded timeout. Body is a stub. */
CFE_Status_t COMMS_SIM_UDP_Receive(void *Buffer, size_t Size, size_t *Received, int32 TimeoutMs);

#endif /* COMMS_SIM_UDP_H */
