import Foundation

/// How Test All Outputs plays: which outputs, what signal, and whether they sound together.
struct OutputTestPlan: Equatable {
    enum Timing: String, CaseIterable, Identifiable {
        case simultaneous
        case series

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .simultaneous: return "All at Once"
            case .series: return "In Series"
            }
        }
    }

    enum Signal: String, CaseIterable, Identifiable {
        case announce
        case noise

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .announce: return "Announce"
            case .noise: return "Pink Noise"
            }
        }
    }

    enum Scope: String, CaseIterable, Identifiable {
        case all
        case inUse

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "All Outputs"
            case .inUse: return "In Use"
            }
        }
    }

    var timing: Timing = .series
    var signal: Signal = .announce
    var scope: Scope = .all

    /// The outputs this plan tests, ordered by first hardware channel.
    ///
    /// `.all` lists every hardware channel as a mono output. `.inUse` lists each distinct
    /// destination in `routed` once, skipping `.none` and any that the device cannot reach.
    /// Announcing all at once always uses mono outputs, so each channel speaks only its own
    /// number instead of a stereo pair's phrase landing on top of another output's.
    func destinations(channelCount: Int, routed: [OutputDestination]) -> [OutputDestination] {
        let count = max(channelCount, 1)
        switch scope {
        case .all:
            return (1...count).map { OutputDestination.mono(channel: $0) }
        case .inUse:
            let reachable = routed.filter { destination in
                guard let range = Self.channelRange(of: destination) else { return false }
                return range.upperBound <= count
            }
            if timing == .simultaneous && signal == .announce {
                let channels = Set(reachable.compactMap(Self.channelRange(of:)).flatMap { $0 })
                return channels.sorted().map { OutputDestination.mono(channel: $0) }
            }
            var seen = Set<OutputDestination>()
            let distinct = reachable.filter { seen.insert($0).inserted }
            return distinct.sorted { lhs, rhs in
                let left = Self.channelRange(of: lhs)?.lowerBound ?? 0
                let right = Self.channelRange(of: rhs)?.lowerBound ?? 0
                if left != right { return left < right }
                // A stereo pair sorts before a mono output on its first channel.
                return Self.channelRange(of: lhs)?.count ?? 0 > Self.channelRange(of: rhs)?.count ?? 0
            }
        }
    }

    /// One-based hardware channels a destination plays on.
    private static func channelRange(of destination: OutputDestination) -> ClosedRange<Int>? {
        switch destination {
        case .none:
            return nil
        case .mono(let channel):
            return channel >= 1 ? channel...channel : nil
        case .stereoPair(let startChannel):
            return startChannel >= 1 ? startChannel...(startChannel + 1) : nil
        }
    }
}
