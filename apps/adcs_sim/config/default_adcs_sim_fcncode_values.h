#ifndef DEFAULT_ADCS_SIM_FCNCODE_VALUES_H
#define DEFAULT_ADCS_SIM_FCNCODE_VALUES_H

#define ADCS_SIM_CCVAL(x) ADCS_SIM_FunctionCode_##x

enum ADCS_SIM_FunctionCode_
{
    ADCS_SIM_FunctionCode_NOOP           = 0,
    ADCS_SIM_FunctionCode_RESET_COUNTERS = 1,
    ADCS_SIM_FunctionCode_SEND_HELLO     = 2, /* placeholder ADCS command */

    /*
     * SIMULATION-ONLY FAULT HOOK (Phase 6). Not flight behaviour.
     * Makes the app stop doing its periodic work while remaining loaded and
     * running, so HS's application monitor can detect a stalled app.
     */
    ADCS_SIM_FunctionCode_INJECT_STALL   = 3,
};

#endif
