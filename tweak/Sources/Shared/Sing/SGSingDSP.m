#include "SGSingDSP.h"
#include <math.h>
#include <stdatomic.h>

static const double kLevelRampSeconds = 0.030;
static const double kBypassRampSeconds = 0.120;
static atomic_bool sg_spatialVoice = false;

void SGSingDSPSetSpatialVoice(bool enabled) { atomic_store_explicit(&sg_spatialVoice, enabled, memory_order_relaxed); }
bool SGSingDSPSpatialVoice(void) { return atomic_load_explicit(&sg_spatialVoice, memory_order_relaxed); }

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
    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            m->instrumental += m->instrumentalStep;

            if (!--m->remaining) {
                m->gain = m->targetGain;
                m->instrumental = m->instrumentalTarget;
            }
        }

        for (unsigned c = 0; c < 2; c++) {
            size_t at = (size_t)i * 2 + c;

            float source = isfinite(original[at]) ? original[at] : 0;
            float vocal = isfinite(vocals[at]) ? vocals[at] : 0;

            if (SGSingDSPSpatialVoice()) {
                size_t leftAt = (size_t)i * 2;
                size_t rightAt = leftAt + 1;
                float left = isfinite(vocals[leftAt]) ? vocals[leftAt] : 0;
                float right = isfinite(vocals[rightAt]) ? vocals[rightAt] : 0;
                // The separated vocal stem is often already narrow. Keep only its mid channel
                // so Spatial Voice produces a deterministic front/center vocal instead of an
                // almost inaudible 75% side reduction.
                float mid = 0.5f * (left + right);
                vocal = mid;
            }

            // instrumental = original - vocal
            float value =
                m->instrumental * (source - vocal)
                + m->gain * vocal;

            out[at] = fmaxf(-1, fminf(1, value));
        }
    }
}
