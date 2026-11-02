#pragma once
#include <math.h>
#include <string.h>

// Four inexpensive frequency bands; no audio history, FFT, or heap allocation.
typedef struct {
    float low[3], coefficient[3], levels[4];
    double energy[4], inputEnergy;
    unsigned count;
} IslandAudioBands;
static inline void IslandAudioBandsInit(IslandAudioBands *s, double rate) {
    memset(s, 0, sizeof(*s));
    const float cutoff[3] = {250, 1000, 4000};
    for (int i = 0; i < 3; i++) s->coefficient[i] = 1 - expf(-2 * M_PI * cutoff[i] / fmax(8000, rate));
}
static inline int IslandAudioBandsFeed(IslandAudioBands *s, float sample) {
    if (!isfinite(sample)) sample = 0;
    for (int i = 0; i < 3; i++) s->low[i] += s->coefficient[i] * (sample - s->low[i]);
    const float bands[4] = {s->low[0], s->low[1] - s->low[0], s->low[2] - s->low[1], sample - s->low[2]};
    for (int i = 0; i < 4; i++) s->energy[i] += (double)bands[i] * bands[i];
    s->inputEnergy += (double)sample * sample;
    if (++s->count < 1024) return 0;
    const int silent = s->inputEnergy / s->count < 1e-9;
    for (int i = 0; i < 4; i++) {
        float rms = sqrt(s->energy[i] / s->count);
        float target = silent ? 0 : fminf(1, fmaxf(0, (20 * log10f(fmaxf(1e-9, rms)) + 65) / 55));
        s->levels[i] = silent ? 0 : s->levels[i] + (target > s->levels[i] ? 0.8f : 0.4f) * (target - s->levels[i]);
        s->energy[i] = 0;
    }
    s->count = 0; s->inputEnergy = 0;
    return 1;
}
