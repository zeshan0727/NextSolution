#include <assert.h>
#include <math.h>
#include <stdio.h>

static int percent_for_brightness(double value) {
    if (value < 0.0) value = 0.0;
    if (value > 1.0) value = 1.0;
    return (int)lround(value * 100.0);
}

static int should_show(int enabled, int event_received) {
    return enabled && event_received;
}

int main(void) {
    assert(percent_for_brightness(-0.2) == 0);
    assert(percent_for_brightness(0.0) == 0);
    assert(percent_for_brightness(0.004) == 0);
    assert(percent_for_brightness(0.005) == 1);
    assert(percent_for_brightness(0.42) == 42);
    assert(percent_for_brightness(0.995) == 100);
    assert(percent_for_brightness(1.0) == 100);
    assert(percent_for_brightness(1.2) == 100);
    assert(should_show(1, 1) == 1);
    assert(should_show(0, 1) == 0);
    assert(should_show(1, 0) == 0);
    puts("PASS 11/11 deterministic decision cases");
    return 0;
}
