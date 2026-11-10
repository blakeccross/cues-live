#import "PitchShiftBridge.h"

#include "signalsmith-stretch.h"

#include <algorithm>
#include <cstring>
#include <vector>

namespace {

struct ConstBuffers {
    const float *const *channels;

    const float *operator[](int channel) const {
        return channels[channel];
    }
};

struct OffsetConstBuffers {
    const float *const *channels;
    int offset;

    struct Channel {
        const float *samples;

        float operator[](int index) const {
            return samples[index];
        }
    };

    Channel operator[](int channel) const {
        return Channel{channels[channel] + offset};
    }
};

struct OffsetMutableBuffers {
    float *const *channels;
    int offset;

    struct Channel {
        float *samples;

        float &operator[](int index) const {
            return samples[index];
        }
    };

    Channel operator[](int channel) const {
        return Channel{channels[channel] + offset};
    }
};

} // namespace

bool pitch_shift_offline(
    const float *const *inputChannels,
    float *const *outputChannels,
    int channelCount,
    int frameCount,
    double sampleRate,
    int semitoneShift
) {
    if (!inputChannels || !outputChannels || channelCount <= 0 || frameCount <= 0 || sampleRate <= 0) {
        return false;
    }

    if (semitoneShift == 0) {
        for (int channel = 0; channel < channelCount; ++channel) {
            if (!inputChannels[channel] || !outputChannels[channel]) {
                return false;
            }
            std::memcpy(outputChannels[channel], inputChannels[channel], sizeof(float) * static_cast<size_t>(frameCount));
        }
        return true;
    }

    for (int channel = 0; channel < channelCount; ++channel) {
        if (!inputChannels[channel] || !outputChannels[channel]) {
            return false;
        }
    }

    // Fixed seed keeps a given stem deterministic across bakes.
    signalsmith::stretch::SignalsmithStretch<float> stretch(1);
    stretch.presetDefault(channelCount, static_cast<float>(sampleRate));
    stretch.setTransposeSemitones(
        static_cast<float>(semitoneShift),
        static_cast<float>(8000.0 / sampleRate)
    );

    const int seekLength = stretch.outputSeekLength(1);
    const int interval = std::max(1, stretch.intervalSamples());
    // The library's offline recipe flushes the final interval. Files shorter than that
    // are processed at that length and the extra tail is discarded.
    const int renderedFrames = std::max(frameCount, interval + 1);
    const int outputIndex = renderedFrames - interval;
    const int outputPosition = outputIndex + stretch.outputLatency();
    const int inputIndex = outputPosition + stretch.inputLatency();
    const int paddedInputFrames = std::max(inputIndex, seekLength);

    std::vector<std::vector<float>> paddedInput(
        static_cast<size_t>(channelCount),
        std::vector<float>(static_cast<size_t>(paddedInputFrames), 0)
    );
    std::vector<const float *> paddedPointers(static_cast<size_t>(channelCount));
    for (int channel = 0; channel < channelCount; ++channel) {
        const int copyCount = std::min(frameCount, paddedInputFrames);
        std::copy(
            inputChannels[channel],
            inputChannels[channel] + copyCount,
            paddedInput[static_cast<size_t>(channel)].begin()
        );
        paddedPointers[static_cast<size_t>(channel)] = paddedInput[static_cast<size_t>(channel)].data();
    }

    std::vector<std::vector<float>> rendered(
        static_cast<size_t>(channelCount),
        std::vector<float>(static_cast<size_t>(renderedFrames), 0)
    );
    std::vector<float *> renderedPointers(static_cast<size_t>(channelCount));
    for (int channel = 0; channel < channelCount; ++channel) {
        renderedPointers[static_cast<size_t>(channel)] = rendered[static_cast<size_t>(channel)].data();
    }

    const ConstBuffers seekInput{paddedPointers.data()};
    stretch.outputSeek(seekInput, seekLength);

    const int processInputFrames = std::max(0, inputIndex - seekLength);
    if (processInputFrames > 0 && outputIndex > 0) {
        const OffsetConstBuffers processInput{paddedPointers.data(), seekLength};
        const OffsetMutableBuffers processOutput{renderedPointers.data(), 0};
        stretch.process(processInput, processInputFrames, processOutput, outputIndex);
    }

    const int flushStart = std::max(outputIndex, 0);
    const int flushFrames = renderedFrames - flushStart;
    if (flushFrames > 0) {
        const OffsetMutableBuffers flushOutput{renderedPointers.data(), flushStart};
        stretch.flush(flushOutput, flushFrames, 1);
    }

    for (int channel = 0; channel < channelCount; ++channel) {
        std::copy(
            rendered[static_cast<size_t>(channel)].begin(),
            rendered[static_cast<size_t>(channel)].begin() + frameCount,
            outputChannels[channel]
        );
    }
    return true;
}
