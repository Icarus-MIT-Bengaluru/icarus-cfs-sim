#ifndef COMMS_SIM_EVENTIDS_H
#define COMMS_SIM_EVENTIDS_H

/*
 * ICARUS event-ID block for this app. Bases are spaced 20 apart so an event ID
 * alone identifies its originating app:
 *   adcs_sim     1-19
 *   payload_sim 21-39
 *   comms_sim   41-59
 */
#define COMMS_SIM_EID_BASE 40

#define COMMS_SIM_RESERVED_EID      (COMMS_SIM_EID_BASE + 0)
#define COMMS_SIM_INIT_INF_EID      (COMMS_SIM_EID_BASE + 1)  /* startup "hello" */
#define COMMS_SIM_WAKEUP_INF_EID    (COMMS_SIM_EID_BASE + 2)  /* SCH-driven wakeup marker */
#define COMMS_SIM_NOOP_INF_EID      (COMMS_SIM_EID_BASE + 3)
#define COMMS_SIM_RESET_INF_EID     (COMMS_SIM_EID_BASE + 4)
#define COMMS_SIM_CC_ERR_EID        (COMMS_SIM_EID_BASE + 5)
#define COMMS_SIM_MID_ERR_EID       (COMMS_SIM_EID_BASE + 6)
#define COMMS_SIM_CMD_LEN_ERR_EID   (COMMS_SIM_EID_BASE + 7)
#define COMMS_SIM_PIPE_ERR_EID      (COMMS_SIM_EID_BASE + 8)
#define COMMS_SIM_CR_PIPE_ERR_EID   (COMMS_SIM_EID_BASE + 9)
#define COMMS_SIM_SUB_CMD_ERR_EID   (COMMS_SIM_EID_BASE + 10)
#define COMMS_SIM_SUB_HK_ERR_EID    (COMMS_SIM_EID_BASE + 11)
#define COMMS_SIM_UDP_INIT_ERR_EID  (COMMS_SIM_EID_BASE + 12)
#define COMMS_SIM_UDP_SEND_ERR_EID  (COMMS_SIM_EID_BASE + 13)
#define COMMS_SIM_UDP_HELLO_INF_EID (COMMS_SIM_EID_BASE + 14)
#define COMMS_SIM_SUB_WAKEUP_ERR_EID (COMMS_SIM_EID_BASE + 15)

/* Simulation-only fault hook (Phase 6). */
#define COMMS_SIM_STALL_INJECTED_INF_EID (COMMS_SIM_EID_BASE + 16)

#endif
