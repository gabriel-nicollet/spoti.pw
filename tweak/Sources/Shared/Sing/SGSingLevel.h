// Sing level:
// 0%   = instrumental only
// 100% = original mix
// 110% = vocals only
//
// The UI maps these values onto two equal physical sections:
// 0–100% below the midpoint, 100–110% above it.

#pragma once
#include <math.h>

#define SGSingMinimumVocalLevel 0.0f
#define SGSingMaximumVocalLevel 1.1f
#define SGSingOriginalMixLevel 1.0f

static inline float SGSingClampLevel(float value) {
    return isfinite(value)
        ? fmaxf(SGSingMinimumVocalLevel,
                fminf(SGSingMaximumVocalLevel, value))
        : SGSingOriginalMixLevel;
}

// Physical slider position:
// 0.0 = instrumental only
// 0.5 = original mix
// 1.0 = vocals only
static inline float SGSingLevelFromPosition(float position) {
    position = fmaxf(0.0f, fminf(1.0f, position));

    if (position <= 0.5f) {
        // 0 → 100%
        return position * 2.0f;
    }

    // 100 → 110%
    return SGSingOriginalMixLevel + (position - 0.5f) * 0.2f;
}

static inline float SGSingPositionFromLevel(float level) {
    level = SGSingClampLevel(level);

    if (level <= SGSingOriginalMixLevel) {
        // 0 → 100% occupies the bottom half.
        return level * 0.5f;
    }

    // 100 → 110% occupies the top half.
    return 0.5f + (level - SGSingOriginalMixLevel) * 5.0f;
}
