#ifndef PitchShiftBridge_h
#define PitchShiftBridge_h

#ifdef __cplusplus
extern "C" {
#endif

/// A real-time Signalsmith Stretch instance for one track. It changes speed and pitch
/// independently while the track plays.
///
/// Create and destroy it off the audio thread. Every other call is allocation-free and may
/// run on the audio thread. Buffers are arrays of `channelCount` planar float channels.
typedef struct LiveStretch LiveStretch;

LiveStretch *live_stretch_create(int channelCount, double sampleRate);
void live_stretch_destroy(LiveStretch *stretch);

/// Input frames the stretcher must be fed ahead of the output position.
int live_stretch_input_latency(const LiveStretch *stretch);
/// Output frames the stretcher holds back; scaled by the playback rate when reading ahead.
int live_stretch_output_latency(const LiveStretch *stretch);

void live_stretch_set_transpose_semitones(LiveStretch *stretch, float semitones);

/// Restarts at a new position. `input` starts at the first frame the next output should
/// play and holds `inputLatency + rate * outputLatency` frames.
void live_stretch_output_seek(LiveStretch *stretch, const float *const *input, int inputFrames);

/// Consumes `inputFrames` and writes `outputFrames`; their ratio is the playback rate.
void live_stretch_process(
    LiveStretch *stretch,
    const float *const *input,
    int inputFrames,
    float *const *output,
    int outputFrames
);

#ifdef __cplusplus
}
#endif

#endif
