#include "SGSingDSP.h"
#include <math.h>
#include <stdatomic.h>

static const double kLevelRampSeconds = 0.030;
static const double kBypassRampSeconds = 0.120;
static atomic_bool sg_spatialVoice = false;
static atomic_int sg_spatialAzimuthMilliDegrees = 0;

void SGSingDSPSetSpatialVoice(bool enabled) {
    atomic_store_explicit(&sg_spatialVoice, enabled, memory_order_relaxed);
    if (!enabled) atomic_store_explicit(&sg_spatialAzimuthMilliDegrees, 0, memory_order_relaxed);
}
bool SGSingDSPSpatialVoice(void) { return atomic_load_explicit(&sg_spatialVoice, memory_order_relaxed); }
void SGSingDSPSetSpatialAzimuthDegrees(float degrees) {
    if (!isfinite(degrees)) degrees = 0;
    if (degrees < -75.0f) degrees = -75.0f;
    if (degrees > 75.0f) degrees = 75.0f;
    atomic_store_explicit(&sg_spatialAzimuthMilliDegrees, (int)lrintf(degrees * 1000.0f), memory_order_relaxed);
}

static void ramp(SGSingMixer *m,
                 float to,
                 float instrumentalTo,
                 double seconds) {
    m->targetGain = to;
    m->instrumentalTarget = instrumentalTo;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
    m->instrumentalStep =
        (instrumentalTo - m->instrumental) / m->remaining;
}

static void apply(SGSingMixer *m, float level, bool vocalsOnly) {
    (void)vocalsOnly;

    float value = SGSingClampLevel(level);

    float vocal;
    float instrumental;

    if (value <= 1.0f) {
        // 0% = instrumental only
        // 100% = original mix
        //
        // Vocal gain rises from 0 → 1.
        // Instrumental stays at 1.
        vocal = value;
        instrumental = 1.0f;
    } else {
        // 100% = original mix
        // 110% = vocals only
        //
        // Vocal stays at full level.
        // Instrumental falls from 1 → 0.
        vocal = 1.0f;
        instrumental = 1.0f - ((value - 1.0f) / 0.1f);
    }

    ramp(m, vocal, instrumental, kLevelRampSeconds);
}

void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    float value = SGSingClampLevel(level);

    float vocal;
    float instrumental;

    if (value <= 1.0f) {
        vocal = value;
        instrumental = 1.0f;
    } else {
        vocal = 1.0f;
        instrumental = 1.0f - ((value - 1.0f) / 0.1f);
    }

    *m = (SGSingMixer){
        .gain = vocal,
        .targetGain = vocal,
        .instrumental = instrumental,
        .instrumentalTarget = instrumental,
        .sampleRate =
            isfinite(rate) && rate >= 8000 && rate <= 192000
                ? rate
                : 44100
    };
}

void SGSingMixerSetLevel(SGSingMixer *m, float level) {
    apply(m, level, m->vocalsOnly);
}

void SGSingMixerSetVocalsOnly(SGSingMixer *m,
                               float level,
                               bool vocalsOnly) {
    apply(m, level, vocalsOnly);
}

void SGSingMixerBypass(SGSingMixer *m) {
    ramp(m, 1, 1, kBypassRampSeconds);
}

void SGSingMixerProcess(SGSingMixer *m,
                        const float *original,
                        const float *vocals,
                        float *out,
                        uint32_t frames) {
    const bool spatial = SGSingDSPSpatialVoice();
    const float targetAzimuth = spatial
        ? (float)atomic_load_explicit(&sg_spatialAzimuthMilliDegrees, memory_order_relaxed) * (float)(3.14159265358979323846 / 180000.0)
        : 0.0f;
    const float azimuthLimit = 1.3090f; // 75 degrees
    const float alpha = (float)(1.0 - exp(-1.0 / (m->sampleRate * 0.020)));
    const uint32_t maxITD = (uint32_t)fmin(31.0, m->sampleRate * 0.00065);
    const uint32_t roomDelayL = (uint32_t)fmin(1023.0, m->sampleRate * 0.013);
    const uint32_t roomDelayR = (uint32_t)fmin(1023.0, m->sampleRate * 0.019);

    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            m->instrumental += m->instrumentalStep;
            if (!--m->remaining) {
                m->gain = m->targetGain;
                m->instrumental = m->instrumentalTarget;
            }
        }

        float sourceL = isfinite(original[(size_t)i * 2]) ? original[(size_t)i * 2] : 0;
        float sourceR = isfinite(original[(size_t)i * 2 + 1]) ? original[(size_t)i * 2 + 1] : 0;
        float vocalL = isfinite(vocals[(size_t)i * 2]) ? vocals[(size_t)i * 2] : 0;
        float vocalR = isfinite(vocals[(size_t)i * 2 + 1]) ? vocals[(size_t)i * 2 + 1] : 0;
        float spatialL = vocalL, spatialR = vocalR;

        if (spatial) {
            // Smooth head motion to avoid zipper noise. A mono source is panned in the
            // listener's frame; the short far-ear delay and quiet reflections add depth.
            m->spatialAzimuth += (targetAzimuth - m->spatialAzimuth) * alpha;
            if (m->spatialAzimuth < -azimuthLimit) m->spatialAzimuth = -azimuthLimit;
            if (m->spatialAzimuth > azimuthLimit) m->spatialAzimuth = azimuthLimit;
            float mono = 0.5f * (vocalL + vocalR) * 0.84f; // slightly farther than dry/center
            float pan = sinf(m->spatialAzimuth) / sinf(azimuthLimit);
            if (pan < -1) pan = -1;
            if (pan > 1) pan = 1;
            float dryL = mono * sqrtf(0.5f * (1.0f - pan));
            float dryR = mono * sqrtf(0.5f * (1.0f + pan));

            uint32_t delayL = m->spatialAzimuth > 0 ? maxITD : 0;
            uint32_t delayR = m->spatialAzimuth < 0 ? maxITD : 0;
            uint32_t write = m->spatialITDIndex;
            m->spatialITD[write] = mono;
            uint32_t readL = (write + 64 - delayL) & 63;
            uint32_t readR = (write + 64 - delayR) & 63;
            float delayedL = m->spatialITD[readL];
            float delayedR = m->spatialITD[readR];
            m->spatialITDIndex = (write + 1) & 63;
            // Blend the delayed far ear very lightly so localization stays stable.
            if (delayL) dryL = dryL * 0.92f + delayedL * sqrtf(0.5f * (1.0f - pan)) * 0.08f;
            if (delayR) dryR = dryR * 0.92f + delayedR * sqrtf(0.5f * (1.0f + pan)) * 0.08f;

            uint32_t roomAt = m->spatialRoomIndex;
            uint32_t tapL = (roomAt + 1024 - roomDelayL) & 1023;
            uint32_t tapR = (roomAt + 1024 - roomDelayR) & 1023;
            float reflectionL = m->spatialRoomL[tapL];
            float reflectionR = m->spatialRoomR[tapR];
            m->spatialRoomL[roomAt] = dryL + reflectionL * 0.18f;
            m->spatialRoomR[roomAt] = dryR + reflectionR * 0.18f;
            m->spatialRoomIndex = (roomAt + 1) & 1023;
            spatialL = dryL + reflectionL * 0.14f;
            spatialR = dryR + reflectionR * 0.14f;
        }

        // Remove the original separated vocal per channel, then add the processed vocal.
        // This keeps the instrumental's stereo image intact instead of centering its side signal.
        float valueL = m->instrumental * (sourceL - vocalL) + m->gain * spatialL;
        float valueR = m->instrumental * (sourceR - vocalR) + m->gain * spatialR;
        out[(size_t)i * 2] = fmaxf(-1, fminf(1, valueL));
        out[(size_t)i * 2 + 1] = fmaxf(-1, fminf(1, valueR));
    }
}
