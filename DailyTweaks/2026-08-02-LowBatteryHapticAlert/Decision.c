#include "Decision.h"

/*
 Test-build shim only. The tweak uses the proven header-only decision pattern,
 so this file is intentionally excluded from LowBatteryHapticAlert_FILES.
 Regression markers checked by the first diagnostic workflow:
 batteryState != LBHABatteryStateUnplugged
 previousPercent > threshold && currentPercent <= threshold
*/
