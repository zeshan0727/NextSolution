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

int LBHAClampThreshold(int threshold);
LBHAAlertDecision LBHADecisionForChange(bool enabled,
                                        bool hasPreviousLevel,
                                        int previousPercent,
                                        int currentPercent,
                                        LBHABatteryState batteryState,
                                        int threshold);

#endif
