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
    // Per-mixer state for the real-time spatial vocal renderer.
    float spatialAzimuth;
    float spatialITD[64];
    uint32_t spatialITDIndex;
    float spatialRoomL[1024], spatialRoomR[1024];
    uint32_t spatialRoomIndex;
} SGSingMixer;

void SGSingMixerInit(SGSingMixer *mixer, double sampleRate, float level);
void SGSingMixerSetLevel(SGSingMixer *mixer, float level);
void SGSingMixerSetVocalsOnly(SGSingMixer *mixer, float level, bool vocalsOnly);
void SGSingMixerProcess(SGSingMixer *mixer, const float *original, const float *vocals, float *output, uint32_t frames);
void SGSingMixerBypass(SGSingMixer *mixer);
// Spatial Voice renders only the separated vocal stem; the instrumental path stays stereo.
void SGSingDSPSetSpatialVoice(bool enabled);
// Relative source azimuth in degrees: negative is left, positive is right. Thread-safe.
void SGSingDSPSetSpatialAzimuthDegrees(float degrees);
bool SGSingDSPSpatialVoice(void);
