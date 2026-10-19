#ifndef DEFAULT_COMMS_SIM_FCNCODE_VALUES_H
#define DEFAULT_COMMS_SIM_FCNCODE_VALUES_H

#define COMMS_SIM_CCVAL(x) COMMS_SIM_FunctionCode_##x

enum COMMS_SIM_FunctionCode_
{
    COMMS_SIM_FunctionCode_NOOP           = 0,
    COMMS_SIM_FunctionCode_RESET_COUNTERS = 1,
    COMMS_SIM_FunctionCode_SEND_HELLO     = 2, /* placeholder Comms command */

    /*
     * SIMULATION-ONLY FAULT HOOK (Phase 6). Not flight behaviour.
     * Makes the app stop doing its periodic work while remaining loaded and
     * running, so HS's application monitor can detect a stalled app.
     */
    COMMS_SIM_FunctionCode_INJECT_STALL   = 3,
};

#endif
