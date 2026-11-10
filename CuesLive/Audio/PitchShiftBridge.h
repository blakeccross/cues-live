#ifndef PitchShiftBridge_h
#define PitchShiftBridge_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Pitch-shifts `frameCount` samples without changing duration.
/// `inputChannels` and `outputChannels` are arrays of `channelCount` planar float buffers.
/// Returns false when the arguments are unusable.
bool pitch_shift_offline(
    const float *const *inputChannels,
    float *const *outputChannels,
    int channelCount,
    int frameCount,
    double sampleRate,
    int semitoneShift
);

#ifdef __cplusplus
}
#endif

#endif
