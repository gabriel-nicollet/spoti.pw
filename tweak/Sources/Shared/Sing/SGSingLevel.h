// The control's full travel represents 0–110% vocals.
// 100% is the original mix, and 110% is vocals only.
// Shared by UI, controller and mixer so touch, accessibility and
// programmatic changes all use the same range.

#pragma once
#include <math.h>

#define SGSingMinimumVocalLevel 0.0f
#define SGSingMaximumVocalLevel 1.1f

static inline float SGSingClampLevel(float value) {
    return isfinite(value)
        ? fmaxf(SGSingMinimumVocalLevel, fminf(SGSingMaximumVocalLevel, value))
        : 1.0f;
}

static inline float SGSingLevelFromPosition(float position) {
    return SGSingMinimumVocalLevel
        + (SGSingMaximumVocalLevel - SGSingMinimumVocalLevel)
        * fmaxf(0.0f, fminf(1.0f, position));
}

static inline float SGSingPositionFromLevel(float level) {
    return (SGSingClampLevel(level) - SGSingMinimumVocalLevel)
        / (SGSingMaximumVocalLevel - SGSingMinimumVocalLevel);
}
