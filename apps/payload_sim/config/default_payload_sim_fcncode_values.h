#ifndef DEFAULT_PAYLOAD_SIM_FCNCODE_VALUES_H
#define DEFAULT_PAYLOAD_SIM_FCNCODE_VALUES_H

#define PAYLOAD_SIM_CCVAL(x) PAYLOAD_SIM_FunctionCode_##x

enum PAYLOAD_SIM_FunctionCode_
{
    PAYLOAD_SIM_FunctionCode_NOOP           = 0,
    PAYLOAD_SIM_FunctionCode_RESET_COUNTERS = 1,
    PAYLOAD_SIM_FunctionCode_SEND_HELLO     = 2, /* placeholder Payload command */

    /*
     * SIMULATION-ONLY FAULT HOOK (Phase 6). Not flight behaviour.
     * Makes the app stop doing its periodic work while remaining loaded and
     * running, so HS's application monitor can detect a stalled app.
     */
    PAYLOAD_SIM_FunctionCode_INJECT_STALL   = 3,
};

#endif
