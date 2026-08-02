#ifndef LBHA_DECISION_H
#define LBHA_DECISION_H

#include <stdbool.h>

typedef enum {
    LBHABatteryStateUnknown = 0,
    LBHABatteryStateUnplugged = 1,
    LBHABatteryStateCharging = 2,
    LBHABatteryStateFull = 3
} LBHABatteryState;

typedef enum {
    LBHAAlertNone = 0,
    LBHAAlertThresholdCrossed = 1
} LBHAAlertDecision;

static inline int LBHAClampThreshold(int threshold) {
    if (threshold < 5) return 5;
    if (threshold > 50) return 50;
    return threshold;
}

static inline LBHAAlertDecision LBHADecisionForChange(bool enabled,
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

#endif
