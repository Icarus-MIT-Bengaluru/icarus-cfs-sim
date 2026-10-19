#ifndef COMMS_SIM_FCNCODES_H
#define COMMS_SIM_FCNCODES_H

#include "comms_sim_fcncode_values.h"

#define COMMS_SIM_NOOP_CC           COMMS_SIM_CCVAL(NOOP)
#define COMMS_SIM_RESET_COUNTERS_CC COMMS_SIM_CCVAL(RESET_COUNTERS)
#define COMMS_SIM_SEND_HELLO_CC     COMMS_SIM_CCVAL(SEND_HELLO)

/* Simulation-only fault hook; see the fcncode values header. */
#define COMMS_SIM_INJECT_STALL_CC   COMMS_SIM_CCVAL(INJECT_STALL)

#endif
