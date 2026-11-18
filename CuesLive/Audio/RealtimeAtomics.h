#ifndef RealtimeAtomics_h
#define RealtimeAtomics_h

#include <stdbool.h>
#include <stdint.h>

/// Lock-free 64-bit atomics for state shared with the audio render thread. Swift 5 has no
/// atomics before the macOS 15 Synchronization module, so these wrap the compiler builtins.
/// Every function is wait-free on arm64 and x86_64 and safe to call from the render thread.

static inline uint64_t realtime_atomic_load_acquire(const uint64_t *value) {
    return __atomic_load_n(value, __ATOMIC_ACQUIRE);
}

static inline void realtime_atomic_store_relaxed(uint64_t *value, uint64_t desired) {
    __atomic_store_n(value, desired, __ATOMIC_RELAXED);
}

static inline void realtime_atomic_store_release(uint64_t *value, uint64_t desired) {
    __atomic_store_n(value, desired, __ATOMIC_RELEASE);
}

/// Sequentially consistent load and store, for handshakes where one thread stores and then
/// loads a different variable and must not have the two reordered.
static inline uint64_t realtime_atomic_load_seq_cst(const uint64_t *value) {
    return __atomic_load_n(value, __ATOMIC_SEQ_CST);
}

static inline void realtime_atomic_store_seq_cst(uint64_t *value, uint64_t desired) {
    __atomic_store_n(value, desired, __ATOMIC_SEQ_CST);
}

/// Adds `delta` and returns the new value.
static inline uint64_t realtime_atomic_add(uint64_t *value, uint64_t delta) {
    return __atomic_add_fetch(value, delta, __ATOMIC_ACQ_REL);
}

/// Replaces `expected` with `desired`; returns false, leaving the value alone, if another
/// thread changed it first.
static inline bool realtime_atomic_compare_exchange(uint64_t *value, uint64_t expected, uint64_t desired) {
    return __atomic_compare_exchange_n(value, &expected, desired, false, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE);
}

static inline void realtime_atomic_fence_acquire(void) {
    __atomic_thread_fence(__ATOMIC_ACQUIRE);
}

static inline void realtime_atomic_fence_release(void) {
    __atomic_thread_fence(__ATOMIC_RELEASE);
}

#endif /* RealtimeAtomics_h */
