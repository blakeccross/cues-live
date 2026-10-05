import Foundation

enum OutputDestination: Codable, Equatable, Hashable, Identifiable {
    case stereoPair(startChannel: Int)
    case mono(channel: Int)

    var id: String {
        switch self {
        case .stereoPair(let startChannel):
            return "stereo-\(startChannel)"
        case .mono(let channel):
            return "mono-\(channel)"
        }
    }

    var displayLabel: String {
        switch self {
        case .stereoPair(let startChannel):
            return "\(startChannel)-\(startChannel + 1)"
        case .mono(let channel):
            return "\(channel) (Mono)"
        }
    }

    /// Spoken line used while identifying this output from settings.
    var testPhrase: String {
        switch self {
        case .stereoPair(let startChannel):
            return "Testing Output \(startChannel) and \(startChannel + 1)"
        case .mono(let channel):
            return "Testing Output \(channel)"
        }
    }

    /// Zero-based buffer channels that should carry this destination's test signal.
    /// Channel 1 is index 0. Out-of-range destinations fall back to the first stereo pair.
    func testChannelIndexes(outputChannelCount: Int) -> [Int] {
        let count = max(outputChannelCount, 1)
        switch self {
        case .mono(let channel):
            let index = channel - 1
            guard index >= 0, index < count else { return [0] }
            return [index]
        case .stereoPair(let startChannel):
            let left = startChannel - 1
            let right = startChannel
            guard left >= 0, right < count else {
                return count >= 2 ? [0, 1] : [0]
            }
            return [left, right]
        }
    }

    static let defaultDestination: OutputDestination = .stereoPair(startChannel: 1)
}
