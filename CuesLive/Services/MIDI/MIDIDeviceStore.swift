import Foundation
import SwiftData

enum MIDIDeviceStore {
    static func sortedDevices(from context: ModelContext) -> [MIDIDevice] {
        let descriptor = FetchDescriptor<MIDIDevice>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func delete(_ device: MIDIDevice, in context: ModelContext) {
        let deviceID = device.id
        let tracks = (try? context.fetch(FetchDescriptor<MIDITrack>())) ?? []
        for track in tracks where track.device?.id == deviceID {
            track.device = nil
        }
        context.delete(device)
        try? context.save()
    }

    static func findDevice(named name: String, in context: ModelContext) -> MIDIDevice? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let devices = sortedDevices(from: context)
        return devices.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}
