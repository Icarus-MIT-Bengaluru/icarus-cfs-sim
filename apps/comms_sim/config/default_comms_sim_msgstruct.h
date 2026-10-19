#ifndef DEFAULT_COMMS_SIM_MSGSTRUCT_H
#define DEFAULT_COMMS_SIM_MSGSTRUCT_H

#include "comms_sim_mission_cfg.h"
#include "comms_sim_msgdefs.h"
#include "cfe_msg_hdr.h"

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_NoopCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_ResetCountersCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_SendHelloCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_SendHkCmd_t;

/* Simulation-only fault hook (Phase 6). Not flight behaviour. */
typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_InjectStallCmd_t;

/* Scheduled wakeup from sch_lab. Header only: 8 bytes, PayloadLength = 0. */
typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} COMMS_SIM_WakeupCmd_t;

typedef struct
{
    CFE_MSG_TelemetryHeader_t TelemetryHeader;
    COMMS_SIM_HkTlm_Payload_t       Payload;
} COMMS_SIM_HkTlm_t;

#endif /* COMMS_SIM_MSGSTRUCT_H */
