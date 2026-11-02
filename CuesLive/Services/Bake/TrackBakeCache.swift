import Foundation

/// Thread-safe cache of HQ-baked stem buffers keyed by source file + semitone shift.
final class TrackBakeCache: @unchecked Sendable {
    static let shared = TrackBakeCache()

    private struct Entry {
        let relativePath: String
        let sourceModificationDate: Date
        let semitones: Int
        let buffer: DecodedStemBuffer
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func lookup(
        trackID: UUID,
        relativePath: String,
        sourceModificationDate: Date,
        semitones: Int
    ) -> DecodedStemBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[trackID],
              entry.relativePath == relativePath,
              entry.sourceModificationDate == sourceModificationDate,
              entry.semitones == semitones else {
            return nil
        }
        return entry.buffer
    }

    func store(
        trackID: UUID,
        relativePath: String,
        sourceModificationDate: Date,
        semitones: Int,
        buffer: DecodedStemBuffer
    ) {
        lock.lock()
        entries[trackID] = Entry(
            relativePath: relativePath,
            sourceModificationDate: sourceModificationDate,
            semitones: semitones,
            buffer: buffer
        )
        lock.unlock()
    }

    func prune(activeTrackIDs: Set<UUID>) {
        lock.lock()
        entries = entries.filter { activeTrackIDs.contains($0.key) }
        lock.unlock()
    }
}
