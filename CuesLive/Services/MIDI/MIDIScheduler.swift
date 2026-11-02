import CoreMIDI
import Foundation

/// Lookahead scheduler that fires MIDI note events in sync with the shared
/// `AudioPlaybackTransport`. A timer polls the transport's master timeline and
/// dispatches upcoming events to `MIDIOutputService` with host-time timestamps.
final class MIDIScheduler {
    /// A fully-resolved event ready to send (device/command already resolved).
    struct ScheduledEvent {
        let timeline: TimeInterval
        let note: Int
        let channel: Int
        let destinationUniqueID: Int32
    }

    private struct DestinationKey: Hashable {
        let uniqueID: Int32
        let channel: Int
    }

    private let transport: AudioPlaybackTransport
    private let output: MIDIOutputService
    private let queue = DispatchQueue(label: "live.cues.midiScheduler", qos: .userInitiated)
    private var timer: DispatchSourceTimer?

    /// Sorted ascending by timeline.
    private var events: [ScheduledEvent] = []
    /// High-water mark: events at or before this timeline are considered already handled.
    private var dispatchedThrough: TimeInterval = 0
    private var isRunning = false

    private let lookahead: TimeInterval = 0.15
    private let tickInterval: DispatchTimeInterval = .milliseconds(20)

    private static var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    init(transport: AudioPlaybackTransport, output: MIDIOutputService = .shared) {
        self.transport = transport
        self.output = output
    }

    // MARK: - Resolution

    /// Resolves song-level events into fully-resolved scheduled events using each
    /// track's device (destination + channel) and the referenced command's note.
    static func scheduledEvents(events: [MIDIEvent], tracks: [MIDITrack]) -> [ScheduledEvent] {
        let tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return events.compactMap { event in
            guard let track = tracksByID[event.trackID],
                  let device = track.device,
                  let uniqueID = device.destinationUniqueID,
                  let command = device.command(withID: event.commandID) else {
                return nil
            }
            return ScheduledEvent(
                timeline: event.timelineSeconds,
                note: command.note,
                channel: device.midiChannel,
                destinationUniqueID: uniqueID
            )
        }
    }

    // MARK: - Configuration

    func configure(events: [ScheduledEvent]) {
        let sorted = events.sorted { $0.timeline < $1.timeline }
        queue.async { [weak self] in
            self?.events = sorted
        }
    }

    /// Merges additional events into the schedule without resetting dispatch state.
    func appendEvents(_ events: [ScheduledEvent]) {
        guard !events.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.events.append(contentsOf: events)
            self.events.sort { $0.timeline < $1.timeline }
        }
    }

    // MARK: - Transport hooks

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            let host = mach_absolute_time()
            let timeline = self.transport.timelineSeconds(atHostTime: host)
            self.chase(toTimeline: timeline)
            self.startTimerLocked()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.timer?.cancel()
            self.timer = nil
        }
    }

    func reset(toTimeline timeline: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }
            self.dispatchedThrough = timeline
            if self.isRunning {
                self.chase(toTimeline: timeline)
            }
        }
    }

    // MARK: - Internals

    private func startTimerLocked() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard isRunning, transport.isPlaying, !events.isEmpty else { return }

        let nowHost = mach_absolute_time()
        let nowTimeline = transport.timelineSeconds(atHostTime: nowHost)

        // Detect backward jumps (loops / section transitions) and re-chase.
        if nowTimeline < dispatchedThrough - 0.05 {
            chase(toTimeline: nowTimeline)
            return
        }

        let windowEnd = nowTimeline + lookahead
        let rate = localTimelineRate(atHostTime: nowHost, currentTimeline: nowTimeline)

        for event in events where event.timeline > dispatchedThrough && event.timeline <= windowEnd {
            let wallSeconds = max(0, (event.timeline - nowTimeline) / rate)
            let hostTime: MIDITimeStamp = wallSeconds <= 0 ? nowHost : nowHost &+ Self.hostTicks(forSeconds: wallSeconds)
            output.sendNote(
                note: event.note,
                channel: event.channel,
                toUniqueID: event.destinationUniqueID,
                atHostTime: hostTime
            )
        }

        dispatchedThrough = max(dispatchedThrough, windowEnd)
    }

    /// Re-triggers the most recent event at or before `timeline` for each destination/channel
    /// so external gear lands in the correct state after play/seek/loop. Sent immediately.
    private func chase(toTimeline timeline: TimeInterval) {
        var latestByDestination: [DestinationKey: ScheduledEvent] = [:]
        for event in events where event.timeline <= timeline + 0.0001 {
            let key = DestinationKey(uniqueID: event.destinationUniqueID, channel: event.channel)
            if let existing = latestByDestination[key], existing.timeline >= event.timeline {
                continue
            }
            latestByDestination[key] = event
        }

        for event in latestByDestination.values {
            output.sendNote(
                note: event.note,
                channel: event.channel,
                toUniqueID: event.destinationUniqueID,
                atHostTime: 0
            )
        }

        dispatchedThrough = timeline
    }

    /// Local d(timeline)/d(wall) rate, accounting for tempo-mapped playback.
    private func localTimelineRate(atHostTime hostTime: UInt64, currentTimeline: TimeInterval) -> Double {
        let probe = Self.hostTicks(forSeconds: 0.001)
        let future = transport.timelineSeconds(atHostTime: hostTime &+ probe)
        let rate = (future - currentTimeline) / 0.001
        guard rate.isFinite, rate > 0.0001 else { return 1.0 }
        return rate
    }

    private static func hostTicks(forSeconds seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        let nanos = seconds * 1_000_000_000
        let ticks = nanos * Double(timebase.denom) / Double(timebase.numer)
        return UInt64(max(0, ticks))
    }
}
