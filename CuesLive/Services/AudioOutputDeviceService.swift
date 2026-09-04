import AVFoundation
import Foundation
#if os(macOS)
import CoreAudio
#endif

struct AudioOutputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let channelCount: Int
}

enum AudioOutputDeviceService {
    /// Large I/O quantum for playback stability (no recording / monitoring path).
    static let stableBufferFrameSize: UInt32 = 2048

    static func availableDevices() -> [AudioOutputDevice] {
        #if os(macOS)
        return macOSDevices()
        #else
        return iOSDevices()
        #endif
    }

    /// Binds the engine's output unit to a device (macOS) without changing the
    /// system-wide default output. Falls back to the Core Audio property API
    /// when `setDeviceID` is unavailable.
    @discardableResult
    static func bindOutputDevice(uid: String, to engine: AVAudioEngine) -> Bool {
        #if os(macOS)
        guard let deviceID = deviceID(forUID: uid) else { return false }
        engine.prepare()

        do {
            try engine.outputNode.auAudioUnit.setDeviceID(deviceID)
            applyStableBufferSize(to: deviceID)
            return true
        } catch {
            // Fall through to AudioUnitSetProperty.
        }

        guard let audioUnit = engine.outputNode.audioUnit else { return false }
        var mutableID = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            size
        )
        if status == noErr {
            applyStableBufferSize(to: deviceID)
            return true
        }
        return false
        #else
        _ = (uid, engine)
        return false
        #endif
    }

    /// Multi-channel PCM format for the engine graph (standard layout, discrete fallback).
    static func multiChannelFormat(sampleRate: Double, channelCount: Int) -> AVAudioFormat? {
        let channels = max(channelCount, 2)
        let rate = sampleRate > 0 ? sampleRate : DecodedStemBuffer.engineSampleRate

        if let standard = AVAudioFormat(
            standardFormatWithSampleRate: rate,
            channels: AVAudioChannelCount(channels)
        ) {
            return standard
        }

        guard let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
        ) else {
            return nil
        }

        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            interleaved: false,
            channelLayout: layout
        )
    }

    /// Prefer a large hardware / session buffer to reduce underruns during multitrack playback.
    /// On macOS, prefers the given device when provided; otherwise uses the current system default.
    @discardableResult
    static func applyStableBufferSize(deviceUID: String? = nil) -> Bool {
        #if os(macOS)
        let deviceID = deviceUID.flatMap { self.deviceID(forUID: $0) }
        return applyMacOSStableBufferSize(to: deviceID)
        #else
        _ = deviceUID
        return applyIOSStableBufferSize()
        #endif
    }

    static func channelCount(for deviceUID: String?) -> Int {
        if let deviceUID, let device = availableDevices().first(where: { $0.id == deviceUID }) {
            return device.channelCount
        }
        return currentSystemChannelCount()
    }

    static func currentSystemChannelCount() -> Int {
        #if os(macOS)
        return macOSDefaultOutputChannelCount()
        #else
        return iOSOutputChannelCount()
        #endif
    }

    #if os(macOS)
    private static func macOSDevices() -> [AudioOutputDevice] {
        var deviceIDs = [AudioDeviceID]()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard hasOutputChannels(deviceID: deviceID) else { return nil }
            guard let uid = deviceUID(for: deviceID), let name = deviceName(for: deviceID) else { return nil }
            // Ephemeral Core Audio aggregates (CADefaultDeviceAggregate-*) are
            // process-local and must not be persisted or rebound later.
            if uid.hasPrefix("CADefaultDeviceAggregate") { return nil }
            let channels = outputChannelCount(for: deviceID)
            guard channels > 0 else { return nil }
            return AudioOutputDevice(id: uid, name: name, channelCount: channels)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func applyStableBufferSize(to deviceID: AudioDeviceID) {
        _ = applyMacOSStableBufferSize(to: deviceID)
    }

    private static func applyMacOSStableBufferSize(to deviceID: AudioDeviceID?) -> Bool {
        guard let deviceID = deviceID ?? defaultOutputDeviceID() else { return false }
        let frames = clampedBufferFrameSize(stableBufferFrameSize, for: deviceID)
        var mutableFrames = frames
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            size,
            &mutableFrames
        ) == noErr
    }

    private static func clampedBufferFrameSize(_ preferred: UInt32, for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &range) == noErr else {
            return preferred
        }

        let minimum = UInt32(max(1, range.mMinimum.rounded(.up)))
        let maximum = UInt32(max(Double(minimum), range.mMaximum.rounded(.down)))
        return min(max(preferred, minimum), maximum)
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    private static func macOSDefaultOutputChannelCount() -> Int {
        guard let deviceID = defaultOutputDeviceID() else { return 2 }
        return max(outputChannelCount(for: deviceID), 2)
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var deviceIDs = [AudioDeviceID]()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return nil }

        return deviceIDs.first { deviceUID(for: $0) == uid }
    }

    private static func hasOutputChannels(deviceID: AudioDeviceID) -> Bool {
        outputChannelCount(for: deviceID) > 0
    }

    private static func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else { return 0 }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferList) == noErr else {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid) == noErr else {
            return nil
        }
        return uid as String
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else {
            return nil
        }
        return name as String
    }
    #else
    private static func iOSDevices() -> [AudioOutputDevice] {
        let session = AVAudioSession.sharedInstance()
        let routeOutputs = session.currentRoute.outputs
        if routeOutputs.isEmpty {
            return [
                AudioOutputDevice(
                    id: "ios-default",
                    name: "Current Output",
                    channelCount: iOSOutputChannelCount()
                ),
            ]
        }

        return routeOutputs.map { port in
            AudioOutputDevice(
                id: port.uid,
                name: port.portName,
                channelCount: iOSOutputChannelCount()
            )
        }
    }

    private static func iOSOutputChannelCount() -> Int {
        let session = AVAudioSession.sharedInstance()
        return max(session.outputNumberOfChannels, 2)
    }

    private static func applyIOSStableBufferSize() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let sampleRate = session.sampleRate > 0 ? session.sampleRate : DecodedStemBuffer.engineSampleRate
        let duration = Double(stableBufferFrameSize) / sampleRate
        do {
            try session.setPreferredIOBufferDuration(duration)
            return true
        } catch {
            return false
        }
    }
    #endif
}
