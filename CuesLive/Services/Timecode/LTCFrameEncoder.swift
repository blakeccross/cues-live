import Foundation

enum LTCFrameEncoder {
    /// SMPTE sync word value packed LSB-first into bits 64–79 (libltc-compatible).
    static let syncWord: UInt16 = 0x3FFD

    /// Returns 80 bits (bit 0 = LSB / first transmitted).
    static func bits(
        for timecode: TimecodeValue,
        frameRate: TimecodeFrameRate
    ) -> [Bool] {
        var bits = Array(repeating: false, count: 80)

        let hours = ((timecode.hours % 24) + 24) % 24
        let minutes = min(59, max(0, timecode.minutes))
        let seconds = min(59, max(0, timecode.seconds))
        let frames = min(frameRate.timecodeFramesPerSecond - 1, max(0, timecode.frames))

        setBCD(frames % 10, into: &bits, startBit: 0, digitBits: 4)
        setBCD(frames / 10, into: &bits, startBit: 8, digitBits: 2)
        bits[10] = frameRate.isDropFrame
        bits[11] = false // color frame

        setBCD(seconds % 10, into: &bits, startBit: 16, digitBits: 4)
        setBCD(seconds / 10, into: &bits, startBit: 24, digitBits: 3)

        setBCD(minutes % 10, into: &bits, startBit: 32, digitBits: 4)
        setBCD(minutes / 10, into: &bits, startBit: 40, digitBits: 3)

        setBCD(hours % 10, into: &bits, startBit: 48, digitBits: 4)
        setBCD(hours / 10, into: &bits, startBit: 56, digitBits: 2)

        // Binary group flags unused (zeros) for basic wall-clock LTC.
        // Bit positions differ for 25 fps vs 24/30; leave all clear.

        var sync = syncWord
        for offset in 0..<16 {
            bits[64 + offset] = (sync & 1) == 1
            sync >>= 1
        }

        applyParity(to: &bits, frameRate: frameRate)
        return bits
    }

    static func applyParity(to bits: inout [Bool], frameRate: TimecodeFrameRate) {
        precondition(bits.count == 80)
        let parityBitIndex = frameRate == .fps25 ? 59 : 27
        bits[parityBitIndex] = false
        let zeroCount = bits.reduce(0) { $0 + ($1 ? 0 : 1) }
        // Even number of zeros keeps sync-word phase consistent.
        if zeroCount % 2 != 0 {
            bits[parityBitIndex] = true
        }
    }

    private static func setBCD(
        _ value: Int,
        into bits: inout [Bool],
        startBit: Int,
        digitBits: Int
    ) {
        var remaining = max(0, value)
        for offset in 0..<digitBits {
            bits[startBit + offset] = (remaining & 1) == 1
            remaining >>= 1
        }
    }
}
