import Foundation

/// Holds a value that any thread, including the audio render thread, can read and update
/// without taking a lock.
///
/// Every update writes a complete new copy into a free slot and then swings `current` to it
/// with a compare-and-swap. Readers copy whichever slot is current and re-check its stamp
/// afterwards, so they never see a half-written value and never wait for a writer. A writer
/// that loses the race to another writer recomputes from the newer value.
///
/// `Value` must be plain data: numbers, flags, and structs or optionals made of them.
/// Copying it must not retain anything, or a copy taken on the render thread could end up
/// releasing the last reference there.
final class RealtimeSnapshot<Value: Equatable>: @unchecked Sendable {
    /// Far more than the number of threads that ever write at once, so a writer always
    /// finds a free slot. At most 256: the slot index takes the low 8 bits of `current`.
    private static var slotCount: Int { 32 }
    /// Stamp of a slot that has never held a published value. Lower than every version.
    private static var unusedStamp: UInt64 { 1 }
    /// Stamp of a slot a writer has claimed and is still filling.
    private static var claimedStamp: UInt64 { 0 }

    /// The published version and the slot holding it, packed by `pack(version:slot:)`.
    /// Versions only grow, because a writer's version is newer than the one it replaces.
    private let current: UnsafeMutablePointer<UInt64>
    /// Last version handed to a writer, published or not.
    private let lastVersion: UnsafeMutablePointer<UInt64>
    /// Version each slot holds, or `claimedStamp` while a writer fills it.
    private let stamps: UnsafeMutablePointer<UInt64>
    private let values: UnsafeMutablePointer<Value>

    init(_ initial: Value) {
        assert(_isPOD(Value.self), "RealtimeSnapshot values must not hold references")
        let count = Self.slotCount
        current = .allocate(capacity: 1)
        lastVersion = .allocate(capacity: 1)
        stamps = .allocate(capacity: count)
        values = .allocate(capacity: count)
        stamps.initialize(repeating: Self.unusedStamp, count: count)
        values.initialize(repeating: initial, count: count)

        let firstVersion = Self.unusedStamp + 1
        stamps[0] = firstVersion
        current.initialize(to: Self.pack(version: firstVersion, slot: 0))
        lastVersion.initialize(to: firstVersion)
    }

    deinit {
        values.deinitialize(count: Self.slotCount)
        values.deallocate()
        stamps.deallocate()
        lastVersion.deallocate()
        current.deallocate()
    }

    /// The latest published value.
    func load() -> Value {
        loadPublished().value
    }

    /// Applies `transform` to the latest value and publishes the result, unless the result
    /// is unchanged. `transform` may run more than once when another thread publishes in
    /// between, so it must only compute from its argument.
    @discardableResult
    func update<Result>(_ transform: (inout Value) -> Result) -> Result {
        while true {
            let (published, value) = loadPublished()
            var next = value
            let result = transform(&next)
            guard next != value else { return result }

            if realtime_atomic_compare_exchange(current, published, write(next)) {
                return result
            }
        }
    }

    private func loadPublished() -> (word: UInt64, value: Value) {
        while true {
            let word = realtime_atomic_load_acquire(current)
            let (version, slot) = Self.unpack(word)
            // A mismatch means the slot was recycled after `current` was read; the next
            // read of `current` finds a newer version.
            guard realtime_atomic_load_acquire(stamps + slot) == version else { continue }
            let value = values[slot]
            realtime_atomic_fence_acquire()
            if realtime_atomic_load_acquire(stamps + slot) == version {
                return (word, value)
            }
        }
    }

    /// Fills a free slot with `value` and returns its packed word, unpublished.
    private func write(_ value: Value) -> UInt64 {
        let version = realtime_atomic_add(lastVersion, 1)
        let slot = claimSlot()
        values[slot] = value
        realtime_atomic_store_release(stamps + slot, version)
        return Self.pack(version: version, slot: slot)
    }

    /// Claims a slot whose version is older than the published one. Versions only grow, so
    /// such a slot can never be published again, and the compare-and-swap keeps two writers
    /// from claiming the same one. A writer stalled mid-fill keeps its slot claimed rather
    /// than stamping over a slot someone else has since published.
    private func claimSlot() -> Int {
        while true {
            let publishedVersion = Self.unpack(realtime_atomic_load_acquire(current)).version
            for slot in 0..<Self.slotCount {
                let stamp = realtime_atomic_load_acquire(stamps + slot)
                if stamp != Self.claimedStamp, stamp < publishedVersion,
                   realtime_atomic_compare_exchange(stamps + slot, stamp, Self.claimedStamp) {
                    return slot
                }
            }
        }
    }

    private static func pack(version: UInt64, slot: Int) -> UInt64 {
        version << 8 | UInt64(slot)
    }

    private static func unpack(_ word: UInt64) -> (version: UInt64, slot: Int) {
        (word >> 8, Int(word & 0xFF))
    }
}
