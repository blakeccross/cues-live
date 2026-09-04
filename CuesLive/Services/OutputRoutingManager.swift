import AVFoundation
import Foundation

enum OutputRoutingManager {
    /// Routes track playback nodes to hardware outs via AU channel maps.
    ///
    /// Tracks are connected with a multi-channel format matching the device so the
    /// AU channel map length is valid. Map **values** never reference source
    /// channels past `sourceChannelCount` (mono stems use dual-mono `0/0`, never
    /// `0/1`). Returns `false` when the device is stereo-only so the caller can
    /// use the master-mixer path.
    @discardableResult
    static func applyChannelMapRouting(
        engine: AVAudioEngine,
        tracks: [(node: AVAudioNode, format: AVAudioFormat, destination: OutputDestination)],
        outputChannelCount: Int
    ) -> Bool {
        let channelCount = max(outputChannelCount, 2)
        guard channelCount > 2 else { return false }

        guard let multiChannelFormat = AudioOutputDeviceService.multiChannelFormat(
            sampleRate: DecodedStemBuffer.engineSampleRate,
            channelCount: channelCount
        ) else {
            return false
        }

        engine.disconnectNodeOutput(engine.mainMixerNode)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: multiChannelFormat)

        var connectedTracks = 0
        for track in tracks {
            let sourceChannels = max(1, Int(track.format.channelCount))
            let map = channelMap(
                for: track.destination,
                outputChannelCount: channelCount,
                sourceChannelCount: sourceChannels
            )
            guard map.contains(where: { $0.intValue >= 0 }) else { continue }

            engine.disconnectNodeOutput(track.node)
            track.node.auAudioUnit.channelMap = nil
            // Connection format must match map length (device channel count).
            // Source/render format stays whatever the node was created with;
            // unused mapped inputs are never referenced for mono stems.
            engine.connect(track.node, to: engine.mainMixerNode, format: multiChannelFormat)
            track.node.auAudioUnit.channelMap = map
            connectedTracks += 1
        }

        return connectedTracks > 0
    }

    static func channelMap(
        for destination: OutputDestination,
        outputChannelCount: Int,
        sourceChannelCount: Int = 2
    ) -> [NSNumber] {
        let sourceChannels = max(1, sourceChannelCount)
        let rightSource = sourceChannels >= 2 ? 1 : 0
        var map = Array(repeating: NSNumber(value: -1), count: outputChannelCount)
        switch destination {
        case .stereoPair(let start):
            let left = start - 1
            let right = start
            guard left >= 0, right < outputChannelCount else {
                return defaultStereoMap(outputChannelCount, sourceChannelCount: sourceChannels)
            }
            map[left] = 0
            // Dual-mono when the stem is mono: both outs read input channel 0.
            map[right] = NSNumber(value: rightSource)
        case .mono(let channel):
            let index = channel - 1
            guard index >= 0, index < outputChannelCount else {
                return defaultStereoMap(outputChannelCount, sourceChannelCount: sourceChannels)
            }
            map[index] = 0
        }
        return map
    }

    static func defaultStereoMap(_ count: Int, sourceChannelCount: Int = 2) -> [NSNumber] {
        let rightSource = sourceChannelCount >= 2 ? 1 : 0
        var map = Array(repeating: NSNumber(value: -1), count: count)
        if count >= 1 { map[0] = 0 }
        if count >= 2 { map[1] = NSNumber(value: rightSource) }
        return map
    }

    static func clearChannelMap(on node: AVAudioNode) {
        // `nil` restores the unit's natural identity map. A hard-coded `[0, 1]`
        // assumes stereo inputs and crashes Core Audio when applied to mono stems.
        node.auAudioUnit.channelMap = nil
    }
}
