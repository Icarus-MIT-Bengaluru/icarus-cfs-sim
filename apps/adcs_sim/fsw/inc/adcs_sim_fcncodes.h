#ifndef ADCS_SIM_FCNCODES_H
#define ADCS_SIM_FCNCODES_H

#include "adcs_sim_fcncode_values.h"

#define ADCS_SIM_NOOP_CC           ADCS_SIM_CCVAL(NOOP)
#define ADCS_SIM_RESET_COUNTERS_CC ADCS_SIM_CCVAL(RESET_COUNTERS)
#define ADCS_SIM_SEND_HELLO_CC     ADCS_SIM_CCVAL(SEND_HELLO)

/* Simulation-only fault hook; see the fcncode values header. */
#define ADCS_SIM_INJECT_STALL_CC   ADCS_SIM_CCVAL(INJECT_STALL)

#endif
