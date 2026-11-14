import AVFoundation

/// Shapes rendered audio with a clip's fades.
///
/// Runs on the audio render thread: it only reads the clip's values and writes the buffers.
enum ClipFadeRenderer {
    /// Frames between two readings of the fade curve. The gain runs straight between them,
    /// which keeps every curve smooth without evaluating it for each frame.
    static let stepFrames = 32

    /// Multiplies `frameCount` frames of every buffer, from `outputOffset`, by the clip's fades.
    /// `clipOffset` is where the first frame plays, in timeline seconds from the clip's start.
    static func apply(
        _ clip: TrackClip,
        clipOffset: TimeInterval,
        sampleRate: Double,
        to buffers: UnsafeMutableAudioBufferListPointer,
        outputOffset: Int,
        frameCount: Int
    ) {
        guard sampleRate > 0, frameCount > 0 else { return }
        let endOffset = clipOffset + Double(frameCount) / sampleRate
        let inFadeIn = clip.fadeIn.isActive && clipOffset < clip.fadeIn.duration
        let inFadeOut = clip.fadeOut.isActive && endOffset > clip.duration - clip.fadeOut.duration
        guard inFadeIn || inFadeOut else { return }

        var frame = 0
        while frame < frameCount {
            let count = min(stepFrames, frameCount - frame)
            let first = clip.fadeGain(atOffset: clipOffset + Double(frame) / sampleRate)
            // Read at the step's last frame, not the next step's first, so the far end of a
            // fade is not smeared into the audio beside it.
            let last = clip.fadeGain(atOffset: clipOffset + Double(frame + count - 1) / sampleRate)
            if first != 1 || last != 1 {
                let slope = count > 1 ? (last - first) / Float(count - 1) : 0
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let samples = data.advanced(by: outputOffset + frame)
                    for index in 0..<count {
                        samples[index] *= first + slope * Float(index)
                    }
                }
            }
            frame += count
        }
    }
}
