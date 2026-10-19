#ifndef DEFAULT_PAYLOAD_SIM_MSGSTRUCT_H
#define DEFAULT_PAYLOAD_SIM_MSGSTRUCT_H

#include "payload_sim_mission_cfg.h"
#include "payload_sim_msgdefs.h"
#include "cfe_msg_hdr.h"

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_NoopCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_ResetCountersCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_SendHelloCmd_t;

typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_SendHkCmd_t;

/* Simulation-only fault hook (Phase 6). Not flight behaviour. */
typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_InjectStallCmd_t;

/* Scheduled wakeup from sch_lab. Header only: 8 bytes, PayloadLength = 0. */
typedef struct
{
    CFE_MSG_CommandHeader_t CommandHeader;
} PAYLOAD_SIM_WakeupCmd_t;

typedef struct
{
    CFE_MSG_TelemetryHeader_t TelemetryHeader;
    PAYLOAD_SIM_HkTlm_Payload_t       Payload;
} PAYLOAD_SIM_HkTlm_t;

#endif /* PAYLOAD_SIM_MSGSTRUCT_H */
