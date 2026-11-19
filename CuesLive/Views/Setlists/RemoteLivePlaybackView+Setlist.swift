import SwiftUI

extension RemoteLivePlaybackView {
    func remoteRowModels(snapshot: RemoteSessionSnapshot) -> [SetlistRowModel] {
        workingEntries.compactMap { entry in
            if let header = entry.headerTitle, entry.songID == nil {
                let seconds = entry.headerTimeSeconds ?? 0
                return SetlistRowModel(
                    id: entry.id,
                    kind: .header(
                        title: header,
                        timeText: seconds > 0 ? LiveSetlistDurationFormat.clock(for: seconds) : nil
                    )
                )
            }
            guard let songID = entry.songID,
                  let song = snapshot.songs.first(where: { $0.id == songID }),
                  let playbackIndex = entry.playbackIndex else {
                return nil
            }
            return SetlistRowModel(
                id: entry.id,
                kind: .song(SetlistRowModel.Song(
                    title: song.name,
                    durationText: LiveSetlistDurationFormat.clock(for: song.timelineDuration),
                    keyText: remoteSongKeyText(song),
                    bpmText: remoteSongBPMText(song),
                    playbackIndex: playbackIndex,
                    hasSmartGuide: song.smartGuideEnabled,
                    transition: remoteTransition(for: entry, in: workingEntries),
                    sections: song.sections.map { $0.asSection(loopSectionIDs: Set(song.loopSectionIDs)) }
                ))
            )
        }
    }

    /// The host protocol only supports cue / move / remove, so the remote menu is smaller.
    func remoteRowActions(for model: SetlistRowModel) -> SetlistRowActions {
        guard case .song(let song) = model.kind else { return SetlistRowActions() }
        return SetlistRowActions(
            cue: {
                client.send(.goToSong(index: song.playbackIndex, autoPlay: false))
            }
        )
    }

    /// Rows skip entries whose song is missing from the snapshot, so the host is told which
    /// entry the block lands before rather than a row offset.
    func moveWorkingRows(from source: IndexSet, to destination: Int) {
        guard let snapshot else { return }
        let visibleIDs = remoteRowModels(snapshot: snapshot).compactMap { $0.id.base as? UUID }
        let movedIDs = source.filter { $0 < visibleIDs.count }.map { visibleIDs[$0] }
        guard !movedIDs.isEmpty else { return }
        let beforeID = visibleIDs[min(destination, visibleIDs.count)...].first { !movedIDs.contains($0) }
        let sourceOffsets = IndexSet(movedIDs.compactMap { id in workingEntries.firstIndex { $0.id == id } })
        let destinationOffset = beforeID.flatMap { id in workingEntries.firstIndex { $0.id == id } }
            ?? workingEntries.count
        workingEntries.move(fromOffsets: sourceOffsets, toOffset: destinationOffset)
        recomputeWorkingEntryIndices()
        client.send(.moveSetlistEntries(entryIDs: movedIDs, beforeEntryID: beforeID))
    }

    func removeWorkingRows(_ ids: [AnyHashable]) {
        let entryIDs = ids.compactMap { $0.base as? UUID }
        guard !entryIDs.isEmpty else { return }
        workingEntries.removeAll { entryIDs.contains($0.id) }
        recomputeWorkingEntryIndices()
        client.send(.removeSetlistEntries(entryIDs: entryIDs))
    }

    func syncWorkingEntries(from entries: [RemoteSetlistEntryDTO]) {
        workingEntries = entries
    }

    private func recomputeWorkingEntryIndices() {
        var playbackIndex = 0
        for index in workingEntries.indices {
            workingEntries[index].sortOrder = index
            if workingEntries[index].songID != nil {
                workingEntries[index].playbackIndex = playbackIndex
                playbackIndex += 1
            } else {
                workingEntries[index].playbackIndex = nil
            }
        }
    }

    private func remoteSongBPMText(_ song: RemoteSongDTO) -> String? {
        guard let bpm = song.tempoChanges.first?.bpm else { return nil }
        return String(format: "%.0f BPM", bpm.rounded())
    }

    private func remoteSongKeyText(_ song: RemoteSongDTO) -> String? {
        let trimmed = song.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "—", trimmed != "-" else { return nil }
        return trimmed
    }

    private func remoteTransition(
        for entry: RemoteSetlistEntryDTO,
        in entries: [RemoteSetlistEntryDTO]
    ) -> SetlistTransition? {
        guard entry.playbackIndex != nil else { return nil }
        let songEntries = entries.filter { $0.playbackIndex != nil }
        guard let index = songEntries.firstIndex(where: { $0.id == entry.id }),
              index < songEntries.count - 1 else {
            return nil
        }
        return SetlistTransition(rawValue: entry.transition)
    }
}
