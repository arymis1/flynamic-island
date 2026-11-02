#include "AudioBands.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    IslandAudioBands silence, bass, treble;
    IslandAudioBandsInit(&silence, 48000);
    IslandAudioBandsInit(&bass, 48000);
    IslandAudioBandsInit(&treble, 48000);
    for (int i = 0; i < 48000; i++) {
        IslandAudioBandsFeed(&silence, 0);
        IslandAudioBandsFeed(&bass, 0.3f * sinf(2 * M_PI * 80 * i / 48000));
        IslandAudioBandsFeed(&treble, 0.3f * sinf(2 * M_PI * 9000 * i / 48000));
    }
    for (int i = 0; i < 4; i++) assert(silence.levels[i] == 0);
    assert(bass.levels[0] > 0.5 && bass.levels[0] > bass.levels[3]);
    assert(treble.levels[3] > 0.5 && treble.levels[3] > treble.levels[0]);
    for (int i = 0; i < 2048; i++) IslandAudioBandsFeed(&bass, 0);
    for (int i = 0; i < 4; i++) assert(bass.levels[i] == 0);
    for (int i = 0; i < 2048; i++) IslandAudioBandsFeed(&silence, NAN);
    for (int i = 0; i < 4; i++) assert(isfinite(silence.levels[i]) && silence.levels[i] == 0);
    printf("14 audio checks passed: silence, bass/treble response, fast silence reset, and invalid samples. Analyzer state: %zu bytes.\n", sizeof(IslandAudioBands));
}
