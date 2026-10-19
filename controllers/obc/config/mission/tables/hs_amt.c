/*
 * ICARUS Health & Safety application monitor table.
 *
 * Overrides cfs/apps/hs/fsw/tables/hs_amt.c via the MISSION_DEFS/tables
 * mechanism (same as sch_lab_table.c). The cfs/ submodule is never edited.
 *
 * PHASE 6 SCOPE: observe, do not act. Every ICARUS entry uses
 * HS_AMTActType_EVENT, which reports a failure and takes no recovery action.
 * HS_AMTActType_APP_RESTART belongs to Phase 7.
 *
 * Entry rules that silently break this table if violated:
 *   - AppName must be the ES-registered name, which is UPPERCASE for the
 *     ICARUS apps (ADCS_SIM, not adcs_sim). It is matched with
 *     CFE_ES_GetAppIDByName; a mismatch yields "App Monitor App Name not
 *     found" instead of monitoring.
 *   - NullTerm must be literally 0 or HS_ValidateAMTable rejects the whole
 *     table and application monitoring is disabled.
 *   - HS_AMTActType_NOACT does NOT mean "event only" -- it disables the entry
 *     entirely and HS never even looks the app up.
 *
 * CycleCount = 20, deliberately not the stock 10. HS checks whether an app's
 * ES execution counter has advanced, and an app only advances it when it wakes.
 * comms_sim wakes every 10 s (its next-fastest tick is SEND_HK at 5.6 s), so
 * with the HS cycle pinned to 1.0 s by the HS_WAKEUP entry in sch_lab_table.c,
 * a CycleCount of 10 would give a ~10 s window and trip comms_sim falsely.
 * 20 gives a ~20 s detection window, which clears comms_sim comfortably.
 *
 * Detection window = CycleCount x HS cycle = 20 x 1.0 s = ~20 s.
 *
 * Simulation scaffolding, not flight software.
 */
#include "cfe.h"
#include "hs_mission_cfg.h"
#include "hs_tbl.h"
#include "hs_tbldefs.h"
#include "cfe_tbl_filedef.h"

HS_AMTEntry_t HS_AppMon_Tbl[HS_MAX_MONITORED_APPS] = {
    /*          AppName                    NullTerm CycleCount     ActionType */

    /*   0 */ { "CFE_ES",   0, 10, HS_AMTActType_NOACT },
    /*   1 */
    { "CFE_EVS",  0, 10, HS_AMTActType_NOACT },
    /*   2 */
    { "CFE_TIME", 0, 10, HS_AMTActType_NOACT },
    /*   3 */
    { "CFE_TBL",  0, 10, HS_AMTActType_NOACT },
    /*   4 */
    { "CFE_SB",   0, 10, HS_AMTActType_NOACT },
    /*   5 */ /* ICARUS: report-only monitoring of the three subsystem apps */
    { "ADCS_SIM",    0, 20, HS_AMTActType_EVENT },
    /*   6 */
    { "PAYLOAD_SIM", 0, 20, HS_AMTActType_EVENT },
    /*   7 */
    { "COMMS_SIM",   0, 20, HS_AMTActType_EVENT },
    /*   8 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*   9 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  10 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  11 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  12 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  13 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  14 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  15 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  16 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  17 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  18 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  19 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  20 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  21 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  22 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  23 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  24 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  25 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  26 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  27 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  28 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  29 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  30 */
    { "",         0, 10, HS_AMTActType_NOACT },
    /*  31 */
    { "",         0, 10, HS_AMTActType_NOACT },
};

CFE_TBL_FILEDEF(HS_AppMon_Tbl, HS.AppMon_Tbl, HS AppMon Table, hs_amt.tbl)
