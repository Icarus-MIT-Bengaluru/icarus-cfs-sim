/*
 * ICARUS ADCS subsystem simulator application.
 *
 * PHASE 4 SKELETON. Function bodies are intentionally minimal: this file exists
 * to prove cFS integration (registration, EVS, Software Bus, app-owned UDP
 * route), not to implement ADCS behaviour. Fill in the marked bodies.
 *
 * This is simulation scaffolding, not flight software.
 */

#include "adcs_sim.h"
#include "utassert.h"
#include "uttest.h"
#include "utstubs.h"

/*
 * PHASE 4 PLACEHOLDER TEST.
 *
 * This exists to prove the unit-test harness is wired into the cFS build, not
 * to test behaviour. Replace with real cases as the app gains logic: suggested
 * first targets are ADCS_SIM_Init() error paths and ADCS_SIM_VerifyCmdLength().
 */
void Test_ADCS_SIM_Placeholder(void)
{
    /* The app's global data block is addressable and zero-initialisable. */
    memset(&ADCS_SIM_Data, 0, sizeof(ADCS_SIM_Data));
    UtAssert_ZERO(ADCS_SIM_Data.CommandCounter);
    UtAssert_ZERO(ADCS_SIM_Data.WakeupCounter);
    UtAssert_BOOL_FALSE(ADCS_SIM_Data.UdpReady);
}

void UtTest_Setup(void)
{
    UtTest_Add(Test_ADCS_SIM_Placeholder, NULL, NULL, "ADCS_SIM placeholder");
}
