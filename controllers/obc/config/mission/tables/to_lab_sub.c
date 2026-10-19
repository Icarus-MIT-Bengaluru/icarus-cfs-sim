/*
 * ICARUS telemetry-output subscription table.
 *
 * Overrides the cFS sample table, which referenced eleven applications ICARUS
 * does not build. MISSION_DEFS/tables takes priority over an app's own table
 * source, so this file is the active TO_LAB subscription set.
 */
#include "cfe_tbl_filedef.h"
#include "cfe_sb_api_typedefs.h"
#include "to_lab_tbl.h"

#include "cfe_msgids.h"
#include "to_lab_msgids.h"
#include "ci_lab_msgids.h"
#include "hs_msgids.h"

/* ICARUS subsystem applications */
#include "adcs_sim_msgids.h"
#include "payload_sim_msgids.h"
#include "comms_sim_msgids.h"

/* clang-format: off */
TO_LAB_Subs_t TO_LAB_Subs =
{
    .Subs = {
        /* Retained stock applications */
        {CFE_SB_MSGID_WRAP_VALUE(TO_LAB_HK_TLM_MID),          {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(TO_LAB_DATA_TYPES_MID),      {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CI_LAB_HK_TLM_MID),          {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(HS_HK_TLM_MID),              {0, 0}, 1},

        /* cFE core telemetry */
        {CFE_SB_MSGID_WRAP_VALUE(CFE_ES_HK_TLM_MID),          {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_EVS_HK_TLM_MID),         {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_SB_HK_TLM_MID),          {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TBL_HK_TLM_MID),         {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TIME_HK_TLM_MID),        {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TIME_DIAG_TLM_MID),      {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_SB_STATS_TLM_MID),       {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_TBL_REG_TLM_MID),        {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_EVS_LONG_EVENT_MSG_MID), {0, 0}, 16},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_ES_APP_TLM_MID),         {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(CFE_ES_MEMSTATS_TLM_MID),    {0, 0}, 1},

        /* ICARUS subsystem housekeeping telemetry */
        {CFE_SB_MSGID_WRAP_VALUE(ADCS_SIM_HK_TLM_MID),        {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(PAYLOAD_SIM_HK_TLM_MID),     {0, 0}, 1},
        {CFE_SB_MSGID_WRAP_VALUE(COMMS_SIM_HK_TLM_MID),       {0, 0}, 1},

        /* TO_UNUSED entry to mark the end of valid MsgIds */
        {CFE_SB_MSGID_RESERVED, {0, 0}, 0}
    }
};
/* clang-format: on */

CFE_TBL_FILEDEF(TO_LAB_Subs, TO_LAB.Subscriptions, ICARUS TO Sub Tbl, to_lab_sub.tbl)
