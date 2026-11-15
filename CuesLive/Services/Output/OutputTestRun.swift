import AVFoundation

/// Bookkeeping for one Test All Outputs run.
struct OutputTestRun {
    let plan: OutputTestPlan
    let destinations: [OutputDestination]
    let format: AVAudioFormat
    var signals: [OutputDestination: AVAudioPCMBuffer] = [:]
    var failed: Set<OutputDestination> = []
    /// Index of the next output to play in series.
    var cursor = 0
    var scheduledEnd: AVAudioFramePosition = 0
    /// Where each scheduled in-series cycle starts, oldest first.
    var starts: [(frame: AVAudioFramePosition, output: OutputDestination)] = []

    /// The next output that still needs a signal and has not failed.
    var nextUnprepared: OutputDestination? {
        destinations.first { signals[$0] == nil && !failed.contains($0) }
    }

    /// The next output to prepare before building an all-at-once cycle, or nil to build it now.
    ///
    /// Every output whose signal is instant joins the same cycle, so they start together.
    /// A slow signal (speech not yet rendered) only blocks the cycle when nothing is ready,
    /// so playback starts after the first phrase and later phrases join at a cycle boundary.
    func outputToPrepareBeforeCycle(isInstant: (OutputDestination) -> Bool) -> OutputDestination? {
        let nothingReady = signals.isEmpty
        return destinations.first { destination in
            signals[destination] == nil
                && !failed.contains(destination)
                && (nothingReady || isInstant(destination))
        }
    }
}
