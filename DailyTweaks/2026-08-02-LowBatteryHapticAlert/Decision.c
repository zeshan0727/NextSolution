#include "Decision.h"

int LBHAClampThreshold(int threshold) {
    if (threshold < 5) return 5;
    if (threshold > 50) return 50;
    return threshold;
}

LBHAAlertDecision LBHADecisionForChange(bool enabled,
                                        bool hasPreviousLevel,
                                        int previousPercent,
                                        int currentPercent,
                                        LBHABatteryState batteryState,
                                        int threshold) {
    if (!enabled || !hasPreviousLevel) return LBHAAlertNone;
    if (batteryState != LBHABatteryStateUnplugged) return LBHAAlertNone;
    if (previousPercent < 0 || currentPercent < 0) return LBHAAlertNone;

    threshold = LBHAClampThreshold(threshold);
    return previousPercent > threshold && currentPercent <= threshold
        ? LBHAAlertThresholdCrossed
        : LBHAAlertNone;
}
