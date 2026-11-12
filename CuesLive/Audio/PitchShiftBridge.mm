#import "PitchShiftBridge.h"

#include "signalsmith-stretch.h"

struct LiveStretch {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
    double sampleRate;

    // Fixed seed keeps a given stem deterministic from play to play.
    LiveStretch() : stretch(1), sampleRate(0) {}
};

namespace {

struct ConstBuffers {
    const float *const *channels;

    const float *operator[](int channel) const {
        return channels[channel];
    }
};

struct MutableBuffers {
    float *const *channels;

    float *operator[](int channel) const {
        return channels[channel];
    }
};

} // namespace

LiveStretch *live_stretch_create(int channelCount, double sampleRate) {
    if (channelCount <= 0 || sampleRate <= 0) {
        return nullptr;
    }
    auto *live = new LiveStretch();
    live->sampleRate = sampleRate;
    // Configuring sizes every internal buffer, so processing never allocates afterwards.
    live->stretch.presetDefault(channelCount, static_cast<float>(sampleRate));
    return live;
}

void live_stretch_destroy(LiveStretch *stretch) {
    delete stretch;
}

int live_stretch_input_latency(const LiveStretch *stretch) {
    return stretch ? stretch->stretch.inputLatency() : 0;
}

int live_stretch_output_latency(const LiveStretch *stretch) {
    return stretch ? stretch->stretch.outputLatency() : 0;
}

void live_stretch_set_transpose_semitones(LiveStretch *stretch, float semitones) {
    if (!stretch) {
        return;
    }
    // Above about 8 kHz the shift keeps tonal structure rather than chasing every partial.
    stretch->stretch.setTransposeSemitones(semitones, static_cast<float>(8000.0 / stretch->sampleRate));
}

void live_stretch_output_seek(LiveStretch *stretch, const float *const *input, int inputFrames) {
    if (!stretch || !input || inputFrames <= 0) {
        return;
    }
    stretch->stretch.outputSeek(ConstBuffers{input}, inputFrames);
}

void live_stretch_process(
    LiveStretch *stretch,
    const float *const *input,
    int inputFrames,
    float *const *output,
    int outputFrames
) {
    if (!stretch || !input || !output || inputFrames < 0 || outputFrames <= 0) {
        return;
    }
    stretch->stretch.process(ConstBuffers{input}, inputFrames, MutableBuffers{output}, outputFrames);
}
