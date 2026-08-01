#include <assert.h>
#include <stdio.h>
#include "../Decision.h"

int main(void) {
    assert(LPMHDecisionForChange(true, false, false, true) == LPMHHapticNone);
    assert(LPMHDecisionForChange(false, true, false, true) == LPMHHapticNone);
    assert(LPMHDecisionForChange(true, true, false, false) == LPMHHapticNone);
    assert(LPMHDecisionForChange(true, true, false, true) == LPMHHapticEnabled);
    assert(LPMHDecisionForChange(true, true, true, false) == LPMHHapticDisabled);
    puts("Low Power Mode Haptic decision tests passed");
    return 0;
}
