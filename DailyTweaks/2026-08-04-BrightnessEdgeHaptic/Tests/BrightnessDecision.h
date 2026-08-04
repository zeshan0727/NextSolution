#pragma once
#include <stdbool.h>

typedef enum { BEHEdgeStateUnknown=-1, BEHEdgeStateMiddle=0, BEHEdgeStateMinimum=1, BEHEdgeStateMaximum=2 } BEHEdgeState;
typedef enum { BEHHapticDecisionNone=0, BEHHapticDecisionMinimum=1, BEHHapticDecisionMaximum=2 } BEHHapticDecision;

static inline BEHEdgeState BEHClassifyBrightness(double value) {
    if (value <= 0.01) return BEHEdgeStateMinimum;
    if (value >= 0.99) return BEHEdgeStateMaximum;
    return BEHEdgeStateMiddle;
}

static inline BEHHapticDecision BEHDecision(bool enabled, BEHEdgeState previous, BEHEdgeState current) {
    if (!enabled || previous == BEHEdgeStateUnknown || previous == current) return BEHHapticDecisionNone;
    if (current == BEHEdgeStateMinimum) return BEHHapticDecisionMinimum;
    if (current == BEHEdgeStateMaximum) return BEHHapticDecisionMaximum;
    return BEHHapticDecisionNone;
}
