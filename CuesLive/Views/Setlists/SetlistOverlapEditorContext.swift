import Foundation

/// The setlist entry and the pair of songs an overlap editor sheet edits.
struct SetlistOverlapEditorContext: Identifiable {
    let id: String
    let entry: SetlistEntry
    let outgoingSong: Song
    let incomingSong: Song
    let initialStartOffset: TimeInterval
    let outgoingSnapshot: LiveSongWaveformSnapshot?
    let incomingSnapshot: LiveSongWaveformSnapshot?

    init(
        entry: SetlistEntry,
        outgoingSong: Song,
        incomingSong: Song,
        outgoingSnapshot: LiveSongWaveformSnapshot? = nil,
        incomingSnapshot: LiveSongWaveformSnapshot? = nil
    ) {
        self.id = "\(outgoingSong.id.uuidString)-\(incomingSong.id.uuidString)"
        self.entry = entry
        self.outgoingSong = outgoingSong
        self.incomingSong = incomingSong
        self.initialStartOffset = entry.overlapConfig?.startOffsetSeconds ?? 0
        self.outgoingSnapshot = outgoingSnapshot
        self.incomingSnapshot = incomingSnapshot
    }
}
