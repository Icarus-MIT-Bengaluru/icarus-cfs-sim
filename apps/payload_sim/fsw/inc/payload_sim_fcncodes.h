#ifndef PAYLOAD_SIM_FCNCODES_H
#define PAYLOAD_SIM_FCNCODES_H

#include "payload_sim_fcncode_values.h"

#define PAYLOAD_SIM_NOOP_CC           PAYLOAD_SIM_CCVAL(NOOP)
#define PAYLOAD_SIM_RESET_COUNTERS_CC PAYLOAD_SIM_CCVAL(RESET_COUNTERS)
#define PAYLOAD_SIM_SEND_HELLO_CC     PAYLOAD_SIM_CCVAL(SEND_HELLO)

/* Simulation-only fault hook; see the fcncode values header. */
#define PAYLOAD_SIM_INJECT_STALL_CC   PAYLOAD_SIM_CCVAL(INJECT_STALL)

#endif
