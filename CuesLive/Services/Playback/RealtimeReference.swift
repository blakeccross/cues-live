import Foundation

/// Hands an immutable object from the main thread to the audio render thread without
/// locks, and frees replaced objects on the main thread, never the render thread.
///
/// While the render thread uses the current object it names it in a hazard slot. A
/// replaced object is freed as soon as the hazard slot no longer names it. If the render
/// thread is mid-block when the object is replaced, freeing waits for the next `publish`.
///
/// Publish from one thread. Read with `withCurrent` from one render thread at a time.
final class RealtimeReference<Object: AnyObject>: @unchecked Sendable {
    /// The latest published object. Publishing thread only.
    private(set) var latest: Object
    /// Replaced objects the render thread may still be using. Publishing thread only.
    private var retired: [Object] = []
    /// Address of `latest`, for the render thread. Kept alive by `latest`.
    private let current: UnsafeMutablePointer<UInt64>
    /// Address of the object the render thread is using, or 0.
    private let hazard: UnsafeMutablePointer<UInt64>

    init(_ object: Object) {
        latest = object
        current = .allocate(capacity: 1)
        current.initialize(to: Self.address(of: object))
        hazard = .allocate(capacity: 1)
        hazard.initialize(to: 0)
    }

    deinit {
        current.deallocate()
        hazard.deallocate()
    }

    /// Number of replaced objects still held because the render thread was using them.
    var retiredCount: Int { retired.count }

    /// Makes `object` the one the render thread sees from its next `withCurrent`.
    func publish(_ object: Object) {
        retired.append(latest)
        latest = object
        realtime_atomic_store_seq_cst(current, Self.address(of: object))
        let inUse = realtime_atomic_load_seq_cst(hazard)
        retired.removeAll { Self.address(of: $0) != inUse }
    }

    /// Runs `body` with the current object on the render thread, without retaining it.
    func withCurrent<Result>(_ body: (Object) -> Result) -> Result {
        // Re-reading `current` after naming it in `hazard` proves the publisher had not
        // replaced it yet, so the publisher's own hazard check will see it and keep it.
        var address: UInt64
        repeat {
            address = realtime_atomic_load_seq_cst(current)
            realtime_atomic_store_seq_cst(hazard, address)
        } while realtime_atomic_load_seq_cst(current) != address
        defer { realtime_atomic_store_release(hazard, 0) }

        guard let pointer = UnsafeRawPointer(bitPattern: UInt(address)) else {
            preconditionFailure("RealtimeReference always holds an object")
        }
        return Unmanaged<Object>.fromOpaque(pointer)._withUnsafeGuaranteedRef(body)
    }

    private static func address(of object: Object) -> UInt64 {
        UInt64(UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque()))
    }
}
