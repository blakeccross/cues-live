import Foundation

/// The output channels one voice's stereo bus is added onto, resolved from its
/// `OutputDestination` for a device of a given width.
struct MixerRoute: Equatable {
    /// Zero-based output channel for the bus's left channel (a mono stem's only channel).
    let left: Int?
    /// Zero-based output channel for the bus's right channel.
    let right: Int?

    static let silent = MixerRoute(left: nil, right: nil)

    /// A destination that does not fit the device falls back to outputs 1 and 2, so a
    /// stale route never silences a group.
    init(destination: OutputDestination, outputChannelCount: Int) {
        let count = max(outputChannelCount, 2)
        switch destination {
        case .none:
            self = .silent
        case .stereoPair(let startChannel) where startChannel >= 1 && startChannel < count:
            self.init(left: startChannel - 1, right: startChannel)
        case .mono(let channel) where channel >= 1 && channel <= count:
            // A stereo stem sent to one output plays its left channel there.
            self.init(left: channel - 1, right: nil)
        case .stereoPair, .mono:
            self.init(left: 0, right: 1)
        }
    }

    private init(left: Int?, right: Int?) {
        self.left = left
        self.right = right
    }
}
