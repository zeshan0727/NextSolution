#include <assert.h>
#include "../Decision.h"

int main(void) {
    assert(LBHAClampThreshold(1) == 5);
    assert(LBHAClampThreshold(15) == 15);
    assert(LBHAClampThreshold(99) == 50);

    assert(LBHADecisionForChange(true, true, 16, 15, LBHABatteryStateUnplugged, 15) == LBHAAlertThresholdCrossed);
    assert(LBHADecisionForChange(true, true, 15, 14, LBHABatteryStateUnplugged, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(false, true, 16, 15, LBHABatteryStateUnplugged, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(true, false, 16, 15, LBHABatteryStateUnplugged, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(true, true, 16, 15, LBHABatteryStateCharging, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(true, true, 16, 15, LBHABatteryStateFull, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(true, true, -1, 15, LBHABatteryStateUnplugged, 15) == LBHAAlertNone);
    assert(LBHADecisionForChange(true, true, 20, 19, LBHABatteryStateUnplugged, 15) == LBHAAlertNone);
    return 0;
}
