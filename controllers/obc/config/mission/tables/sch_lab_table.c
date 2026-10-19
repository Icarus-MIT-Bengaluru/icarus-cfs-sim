/*
 * ICARUS scheduler table.
 *
 * Overrides the cFS sample table, which referenced eleven applications ICARUS
 * does not build. MISSION_DEFS/tables takes priority over an app's own table
 * source, so this file is the active SCH_LAB schedule.
 *
 * PacketRate is in ticks and TickRate is 10 per second, so an entry's period is
 * PacketRate x 100 ms. 100 ms is an exact multiple of the 10 ms PSP timebase,
 * so there is no sub-tick quantization, and the underlying timer is a
 * CLOCK_MONOTONIC periodic timer whose dispatcher accumulates rather than
 * resets -- long-run drift is zero.
 *
 * THIS TABLE IS THE AUTHORITATIVE RATE DEFINITION. Each app also carries a
 * <APP>_DECLARED_RATE_MHZ constant that it stamps into its wakeup marker; the
 * Phase 5 rate checker compares the achieved rate against that claim, so the
 * two must agree. Change a rate here and change the app's constant to match.
 */
#include "cfe_tbl_filedef.h"
#include "sch_lab_tbl.h"
#include "cfe_sb.h"

#include "cfe_msgids.h"
#include "ci_lab_msgids.h"
#include "to_lab_msgids.h"
#include "hs_msgids.h"

/* ICARUS subsystem applications */
#include "adcs_sim_msgids.h"
#include "payload_sim_msgids.h"
#include "comms_sim_msgids.h"

/* clang-format: off */
SCH_LAB_ScheduleTable_t SCH_TBL_Structure =
{
    .TickRate = 10,
    .Config   = {
        /* cFE core housekeeping */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_ES_SEND_HK_MID),       40, 0}, /* every 4.0 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_EVS_SEND_HK_MID),      42, 0}, /* every 4.2 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TIME_SEND_HK_MID),     44, 0}, /* every 4.4 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_SB_SEND_HK_MID),       46, 0}, /* every 4.6 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TBL_SEND_HK_MID),      48, 0}, /* every 4.8 seconds */

        /* Retained stock applications */
        {CFE_SB_MSGID_WRAP_VALUE(CI_LAB_SEND_HK_MID),       50, 0}, /* every 5.0 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(TO_LAB_SEND_HK_MID),       52, 0}, /* every 5.2 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(HS_SEND_HK_MID),           60, 0}, /* every 6.0 seconds */

        /*
         * Pins the Health & Safety monitoring cycle to exactly 1.0 s. HS will
         * self-pace at ~1.2 s from its own SB receive timeout without this, but
         * an explicit entry makes the fault-detection window arithmetic exact
         * and documentable: window = AMT CycleCount x 1.0 s.
         */
        {CFE_SB_MSGID_WRAP_VALUE(HS_WAKEUP_MID),            10, 0}, /* 1.0 s   ->  1   Hz */

        /*
         * ICARUS applications: housekeeping only. Each app receives its own
         * SEND_HK on its own message ID, which also proves its Software Bus
         * subscription is live.
         */
        {CFE_SB_MSGID_WRAP_VALUE(ADCS_SIM_SEND_HK_MID),     54, 0}, /* every 5.4 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(PAYLOAD_SIM_SEND_HK_MID),  55, 0}, /* every 5.5 seconds */
        {CFE_SB_MSGID_WRAP_VALUE(COMMS_SIM_SEND_HK_MID),    56, 0}, /* every 5.6 seconds */

        /*
         * ICARUS scheduled wakeups -- the Phase 5 rate assignment.
         * Each app's periodic work runs only when its wakeup arrives, so these
         * three numbers are the rates the gate measures.
         */
        {CFE_SB_MSGID_WRAP_VALUE(ADCS_SIM_WAKEUP_MID),       1, 0}, /* 100 ms  -> 10   Hz */
        {CFE_SB_MSGID_WRAP_VALUE(PAYLOAD_SIM_WAKEUP_MID),   10, 0}, /* 1.0 s   ->  1   Hz */
        {CFE_SB_MSGID_WRAP_VALUE(COMMS_SIM_WAKEUP_MID),    100, 0}, /* 10.0 s  ->  0.1 Hz */
    }
};
/* clang-format: on */

CFE_TBL_FILEDEF(SCH_TBL_Structure, SCH_LAB.Schedule, ICARUS Schedule Table, sch_lab_table.tbl)
