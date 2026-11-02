import CoreMIDI
import Foundation
import OSLog

/// Thin CoreMIDI wrapper for sending note messages to external destinations.
/// Owns a single MIDI client + output port for the app. Velocity is fixed
/// (the app intentionally ignores velocity for command triggering).
final class MIDIOutputService {
    static let shared = MIDIOutputService()

    /// Posted when the CoreMIDI setup changes (devices added/removed). UI can
    /// observe this to refresh destination pickers.
    static let destinationsDidChangeNotification = Notification.Name("MIDIOutputServiceDestinationsDidChange")

    struct Destination: Identifiable, Hashable {
        let uniqueID: Int32
        let name: String
        var id: Int32 { uniqueID }
    }

    /// Fixed note-on velocity used for all command triggers.
    static let defaultVelocity: UInt8 = 100
    /// How long a triggered note is held before the note-off, in seconds.
    static let defaultGateSeconds: TimeInterval = 0.15

    private let logger = Logger(subsystem: "live.cues", category: "MIDIOutput")
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var isSetUp = false

    private static var timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private init() {
        setUpIfNeeded()
    }

    private func setUpIfNeeded() {
        guard !isSetUp else { return }

        let clientStatus = MIDIClientCreateWithBlock("cues.live" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: MIDIOutputService.destinationsDidChangeNotification, object: nil)
            }
            _ = self
        }
        guard clientStatus == noErr else {
            logger.error("MIDIClientCreate failed: \(clientStatus, privacy: .public)")
            return
        }

        let portStatus = MIDIOutputPortCreate(client, "cues.live Out" as CFString, &outputPort)
        guard portStatus == noErr else {
            logger.error("MIDIOutputPortCreate failed: \(portStatus, privacy: .public)")
            return
        }

        isSetUp = true
    }

    // MARK: - Destinations

    func availableDestinations() -> [Destination] {
        setUpIfNeeded()
        let count = MIDIGetNumberOfDestinations()
        var result: [Destination] = []
        for index in 0..<count {
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else { continue }
            let uniqueID = integerProperty(endpoint, kMIDIPropertyUniqueID)
            let name = stringProperty(endpoint, kMIDIPropertyDisplayName)
                ?? stringProperty(endpoint, kMIDIPropertyName)
                ?? "Destination \(index + 1)"
            result.append(Destination(uniqueID: uniqueID, name: name))
        }
        return result
    }

    func destinationName(forUniqueID uniqueID: Int32) -> String? {
        availableDestinations().first { $0.uniqueID == uniqueID }?.name
    }

    private func resolveEndpoint(uniqueID: Int32) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var objectType = MIDIObjectType.other
        let status = MIDIObjectFindByUniqueID(uniqueID, &object, &objectType)
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    // MARK: - Sending

    /// Sends a note-on at `hostTime` (0 means "as soon as possible") followed by a
    /// note-off after the gate, to the destination identified by `uniqueID`.
    func sendNote(
        note: Int,
        channel: Int,
        toUniqueID uniqueID: Int32,
        atHostTime hostTime: MIDITimeStamp,
        gateSeconds: TimeInterval = MIDIOutputService.defaultGateSeconds
    ) {
        setUpIfNeeded()
        guard isSetUp, let endpoint = resolveEndpoint(uniqueID: uniqueID) else { return }

        let statusChannel = UInt8(max(0, min(15, channel - 1)))
        let noteByte = clamp7(note)
        let onTime: MIDITimeStamp = hostTime == 0 ? mach_absolute_time() : hostTime
        let offTime = onTime &+ Self.hostTicks(forSeconds: max(0.01, gateSeconds))

        let messages: [(bytes: [UInt8], timestamp: MIDITimeStamp)] = [
            ([0x90 | statusChannel, noteByte, Self.defaultVelocity], onTime),
            ([0x80 | statusChannel, noteByte, 0], offTime),
        ]
        sendMessages(messages, to: endpoint)
    }

    /// Immediate send for editor test affordances.
    func sendNoteTestNow(note: Int, channel: Int, toUniqueID uniqueID: Int32) {
        sendNote(note: note, channel: channel, toUniqueID: uniqueID, atHostTime: 0)
    }

    private func sendMessages(_ messages: [(bytes: [UInt8], timestamp: MIDITimeStamp)], to endpoint: MIDIEndpointRef) {
        guard !messages.isEmpty else { return }

        let bufferSize = 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        buffer.withUnsafeMutableBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            let packetList = base.assumingMemoryBound(to: MIDIPacketList.self)
            var packet = MIDIPacketListInit(packetList)
            for message in messages {
                packet = message.bytes.withUnsafeBufferPointer { messagePtr -> UnsafeMutablePointer<MIDIPacket> in
                    MIDIPacketListAdd(
                        packetList,
                        bufferSize,
                        packet,
                        message.timestamp,
                        message.bytes.count,
                        messagePtr.baseAddress!
                    )
                }
            }
            let status = MIDISend(outputPort, endpoint, packetList)
            if status != noErr {
                logger.error("MIDISend failed: \(status, privacy: .public)")
            }
        }
    }

    private func clamp7(_ value: Int) -> UInt8 {
        UInt8(max(0, min(127, value)))
    }

    private static func hostTicks(forSeconds seconds: TimeInterval) -> UInt64 {
        guard seconds > 0 else { return 0 }
        let nanos = seconds * 1_000_000_000
        let ticks = nanos * Double(timebase.denom) / Double(timebase.numer)
        return UInt64(max(0, ticks))
    }

    // MARK: - Property helpers

    private func stringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func integerProperty(_ object: MIDIObjectRef, _ property: CFString) -> Int32 {
        var value: Int32 = 0
        MIDIObjectGetIntegerProperty(object, property, &value)
        return value
    }
}
