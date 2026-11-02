import CoreMIDI
import Foundation
import OSLog

/// Listens for MIDI note-on messages from every attached source.
final class MIDIInputService {
    static let shared = MIDIInputService()

    /// Posted when sources are added or removed.
    static let sourcesDidChangeNotification = Notification.Name("MIDIInputServiceSourcesDidChange")

    struct Source: Identifiable, Hashable {
        let uniqueID: Int32
        let name: String
        var id: Int32 { uniqueID }
    }

    private let logger = Logger(subsystem: "live.cues", category: "MIDIInput")
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var isSetUp = false
    private var connectedSourceIDs: Set<Int32> = []

    /// Called on the main actor with each note-on (velocity > 0).
    var onNoteOn: ((MIDINoteBinding) -> Void)?

    private init() {}

    func start() {
        setUpIfNeeded()
        refreshConnections()
    }

    func availableSources() -> [Source] {
        setUpIfNeeded()
        let count = MIDIGetNumberOfSources()
        var result: [Source] = []
        for index in 0..<count {
            let endpoint = MIDIGetSource(index)
            guard endpoint != 0 else { continue }
            result.append(
                Source(
                    uniqueID: integerProperty(endpoint, kMIDIPropertyUniqueID),
                    name: displayName(for: endpoint, fallbackIndex: index)
                )
            )
        }
        return result
    }

    private func setUpIfNeeded() {
        guard !isSetUp else { return }

        let clientStatus = MIDIClientCreateWithBlock("cues.live Input" as CFString, &client) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshConnections()
                NotificationCenter.default.post(name: MIDIInputService.sourcesDidChangeNotification, object: nil)
            }
        }
        guard clientStatus == noErr else {
            logger.error("MIDIClientCreate failed: \(clientStatus, privacy: .public)")
            return
        }

        let portStatus = MIDIInputPortCreateWithBlock(client, "cues.live In" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handle(packetList: packetList)
        }
        guard portStatus == noErr else {
            logger.error("MIDIInputPortCreate failed: \(portStatus, privacy: .public)")
            return
        }

        isSetUp = true
    }

    private func refreshConnections() {
        setUpIfNeeded()
        guard isSetUp else { return }

        let sources = availableSources()
        let currentIDs = Set(sources.map(\.uniqueID))
        let staleIDs = connectedSourceIDs.subtracting(currentIDs)

        for uniqueID in staleIDs {
            if let endpoint = resolveSource(uniqueID: uniqueID) {
                MIDIPortDisconnectSource(inputPort, endpoint)
            }
            connectedSourceIDs.remove(uniqueID)
        }

        for source in sources where !connectedSourceIDs.contains(source.uniqueID) {
            guard let endpoint = resolveSource(uniqueID: source.uniqueID) else { continue }
            let status = MIDIPortConnectSource(inputPort, endpoint, nil)
            if status == noErr {
                connectedSourceIDs.insert(source.uniqueID)
            } else {
                logger.error("MIDIPortConnectSource failed: \(status, privacy: .public)")
            }
        }
    }

    private func resolveSource(uniqueID: Int32) -> MIDIEndpointRef? {
        var object = MIDIObjectRef()
        var objectType = MIDIObjectType.other
        let status = MIDIObjectFindByUniqueID(uniqueID, &object, &objectType)
        guard status == noErr, object != 0 else { return nil }
        return object
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else { return }
        var packet = UnsafeRawPointer(packetList).advanced(by: packetOffset).assumingMemoryBound(to: MIDIPacket.self)
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.pointee.length)
            withUnsafeBytes(of: packet.pointee.data) { raw in
                let bytes = Array(raw.bindMemory(to: UInt8.self).prefix(length))
                parseMIDIBytes(bytes)
            }
            packet = UnsafePointer(MIDIPacketNext(packet))
        }
    }

    private func parseMIDIBytes(_ bytes: [UInt8]) {
        var index = 0
        var runningStatus: UInt8 = 0

        while index < bytes.count {
            var status = bytes[index]
            if status < 0x80 {
                guard runningStatus >= 0x80 else { break }
                status = runningStatus
            } else {
                index += 1
                runningStatus = status
            }

            if status >= 0xF0 {
                break
            }

            let command = status & 0xF0
            let channel = Int(status & 0x0F) + 1
            let dataLength = command == 0xC0 || command == 0xD0 ? 1 : 2
            guard index + dataLength <= bytes.count else { break }

            if command == 0x90 {
                let note = Int(bytes[index])
                let velocity = bytes[index + 1]
                if velocity > 0 {
                    emitNoteOn(note: note, channel: channel)
                }
            }

            index += dataLength
        }
    }

    private func emitNoteOn(note: Int, channel: Int) {
        let binding = MIDINoteBinding(
            note: max(0, min(127, note)),
            channel: max(1, min(16, channel)),
            sourceName: nil
        )
        DispatchQueue.main.async { [onNoteOn] in
            onNoteOn?(binding)
        }
    }

    private func displayName(for endpoint: MIDIEndpointRef, fallbackIndex: Int) -> String {
        stringProperty(endpoint, kMIDIPropertyDisplayName)
            ?? stringProperty(endpoint, kMIDIPropertyName)
            ?? "Source \(fallbackIndex + 1)"
    }

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
