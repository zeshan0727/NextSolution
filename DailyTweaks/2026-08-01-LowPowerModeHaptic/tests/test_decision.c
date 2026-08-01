#include <assert.h>
#include <stdio.h>
#include "../Decision.h"

int main(void) {
    /* Initial load and disabled mode must never produce feedback. */
    assert(LPMHDecisionForChange(true, false, false, true) == LPMHHapticNone);
    assert(LPMHDecisionForChange(true, false, true, false) == LPMHHapticNone);
    assert(LPMHDecisionForChange(false, true, false, true) == LPMHHapticNone);
    assert(LPMHDecisionForChange(false, true, true, false) == LPMHHapticNone);

    /* Duplicate notifications with no state transition are rejected. */
    assert(LPMHDecisionForChange(true, true, false, false) == LPMHHapticNone);
    assert(LPMHDecisionForChange(true, true, true, true) == LPMHHapticNone);

    /* Genuine transitions select the matching haptic. */
    assert(LPMHDecisionForChange(true, true, false, true) == LPMHHapticEnabled);
    assert(LPMHDecisionForChange(true, true, true, false) == LPMHHapticDisabled);

    puts("Low Power Mode Haptic decision tests passed");
    return 0;
}
