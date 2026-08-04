#include <assert.h>
#include "BrightnessDecision.h"
int main(void) {
  assert(BEHClassifyBrightness(0.0) == BEHEdgeStateMinimum);
  assert(BEHClassifyBrightness(0.5) == BEHEdgeStateMiddle);
  assert(BEHClassifyBrightness(1.0) == BEHEdgeStateMaximum);
  assert(BEHDecision(true, BEHEdgeStateMiddle, BEHEdgeStateMinimum) == BEHHapticDecisionMinimum);
  assert(BEHDecision(true, BEHEdgeStateMiddle, BEHEdgeStateMaximum) == BEHHapticDecisionMaximum);
  assert(BEHDecision(false, BEHEdgeStateMiddle, BEHEdgeStateMaximum) == BEHHapticDecisionNone);
  assert(BEHDecision(true, BEHEdgeStateMaximum, BEHEdgeStateMaximum) == BEHHapticDecisionNone);
  assert(BEHDecision(true, BEHEdgeStateUnknown, BEHEdgeStateMinimum) == BEHHapticDecisionNone);
  assert(BEHDecision(true, BEHEdgeStateMinimum, BEHEdgeStateMiddle) == BEHHapticDecisionNone);
  return 0;
}
