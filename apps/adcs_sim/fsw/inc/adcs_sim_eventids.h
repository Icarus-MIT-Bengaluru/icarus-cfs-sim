#ifndef ADCS_SIM_EVENTIDS_H
#define ADCS_SIM_EVENTIDS_H

/*
 * ICARUS event-ID block for this app. Bases are spaced 20 apart so an event ID
 * alone identifies its originating app:
 *   adcs_sim     1-19
 *   payload_sim 21-39
 *   comms_sim   41-59
 */
#define ADCS_SIM_EID_BASE 0

#define ADCS_SIM_RESERVED_EID      (ADCS_SIM_EID_BASE + 0)
#define ADCS_SIM_INIT_INF_EID      (ADCS_SIM_EID_BASE + 1)  /* startup "hello" */
#define ADCS_SIM_WAKEUP_INF_EID    (ADCS_SIM_EID_BASE + 2)  /* SCH-driven wakeup marker */
#define ADCS_SIM_NOOP_INF_EID      (ADCS_SIM_EID_BASE + 3)
#define ADCS_SIM_RESET_INF_EID     (ADCS_SIM_EID_BASE + 4)
#define ADCS_SIM_CC_ERR_EID        (ADCS_SIM_EID_BASE + 5)
#define ADCS_SIM_MID_ERR_EID       (ADCS_SIM_EID_BASE + 6)
#define ADCS_SIM_CMD_LEN_ERR_EID   (ADCS_SIM_EID_BASE + 7)
#define ADCS_SIM_PIPE_ERR_EID      (ADCS_SIM_EID_BASE + 8)
#define ADCS_SIM_CR_PIPE_ERR_EID   (ADCS_SIM_EID_BASE + 9)
#define ADCS_SIM_SUB_CMD_ERR_EID   (ADCS_SIM_EID_BASE + 10)
#define ADCS_SIM_SUB_HK_ERR_EID    (ADCS_SIM_EID_BASE + 11)
#define ADCS_SIM_UDP_INIT_ERR_EID  (ADCS_SIM_EID_BASE + 12)
#define ADCS_SIM_UDP_SEND_ERR_EID  (ADCS_SIM_EID_BASE + 13)
#define ADCS_SIM_UDP_HELLO_INF_EID (ADCS_SIM_EID_BASE + 14)
#define ADCS_SIM_SUB_WAKEUP_ERR_EID (ADCS_SIM_EID_BASE + 15)

/* Simulation-only fault hook (Phase 6). */
#define ADCS_SIM_STALL_INJECTED_INF_EID (ADCS_SIM_EID_BASE + 16)

#endif
