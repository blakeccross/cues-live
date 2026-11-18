import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#endif

/// Switching the output device's own sample rate.
extension AudioOutputDeviceService {
    /// How long to wait for a device to report its new rate before carrying on.
    private static let sampleRateSettleTimeout: Duration = .seconds(2)

    /// Asks the output device (the system default when `deviceUID` is nil) to run at
    /// `rate`. On macOS this changes the rate for every app using the device. Returns
    /// `false` when the device does not support the rate or did not switch in time;
    /// playback still works, with the engine converting at the output.
    @discardableResult
    static func requestSampleRate(_ rate: Double, deviceUID: String?) async -> Bool {
        #if os(macOS)
        guard let deviceID = deviceUID.flatMap({ deviceID(forUID: $0) }) ?? defaultOutputDeviceID(),
              supportsSampleRate(rate, deviceID: deviceID) else {
            return false
        }
        if nominalSampleRate(of: deviceID) == rate { return true }

        var address = nominalSampleRateAddress
        var requested = rate
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<Double>.size), &requested
        )
        guard status == noErr else { return false }

        // The switch completes asynchronously; poll without blocking the caller's thread.
        let deadline = ContinuousClock.now + sampleRateSettleTimeout
        while ContinuousClock.now < deadline {
            if nominalSampleRate(of: deviceID) == rate { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
        #else
        _ = deviceUID
        do {
            try AVAudioSession.sharedInstance().setPreferredSampleRate(rate)
            return true
        } catch {
            return false
        }
        #endif
    }

    #if os(macOS)
    private static var nominalSampleRateAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func nominalSampleRate(of deviceID: AudioDeviceID) -> Double? {
        var address = nominalSampleRateAddress
        var rate: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate) == noErr else { return nil }
        return rate
    }

    private static func supportsSampleRate(_ rate: Double, deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        var ranges = [AudioValueRange](
            repeating: AudioValueRange(),
            count: Int(size) / MemoryLayout<AudioValueRange>.size
        )
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &ranges) == noErr else {
            return false
        }
        return ranges.contains { $0.mMinimum <= rate && rate <= $0.mMaximum }
    }
    #endif
}
