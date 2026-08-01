#ifndef LPMH_DECISION_H
#define LPMH_DECISION_H

#include <stdbool.h>

typedef enum {
    LPMHHapticNone = 0,
    LPMHHapticEnabled = 1,
    LPMHHapticDisabled = 2
} LPMHHapticDecision;

static inline LPMHHapticDecision LPMHDecisionForChange(bool tweakEnabled,
                                                        bool hasPreviousState,
                                                        bool previousState,
                                                        bool currentState) {
    if (!tweakEnabled || !hasPreviousState || previousState == currentState) {
        return LPMHHapticNone;
    }
    return currentState ? LPMHHapticEnabled : LPMHHapticDisabled;
}

#endif
