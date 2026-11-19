import AVFoundation

/// One sound the `StemMixer` renders every block: a track, or the Smart Guide voice.
///
/// Called on the audio render thread, so implementations must not lock, allocate, or wait.
protocol MixerVoice: AnyObject {
    /// Writes `frameCount` frames into every channel of `outputBuffer`, overwriting what
    /// is there. Returns `false` when the block is silent, so the mixer can skip it.
    func render(
        frameCount: AVAudioFrameCount,
        hostTime: UInt64,
        outputBuffer: UnsafeMutablePointer<AudioBufferList>
    ) -> Bool
}
