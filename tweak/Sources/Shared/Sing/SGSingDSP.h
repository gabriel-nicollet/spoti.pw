#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "SGSingLevel.h"

typedef struct {
    float gain, targetGain, step;
    uint32_t remaining;
    double sampleRate;
    float instrumental, instrumentalTarget, instrumentalStep;
    bool vocalsOnly;
} SGSingMixer;

void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level);
void SGSingMixerSetVocalsOnly(SGSingMixer *mixer, float level, bool vocalsOnly);
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
void SGSingMixerBypass(SGSingMixer *mixer);
// Spatial Voice focuses the separated vocal stem toward the center/front image without
// changing the existing Sing level curve.
void SGSingDSPSetSpatialVoice(bool enabled);
bool SGSingDSPSpatialVoice(void);
