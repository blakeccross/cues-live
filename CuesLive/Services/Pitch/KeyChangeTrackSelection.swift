import Foundation

enum KeyChangeTrackSelection {
    static let excludedGroupNames: Set<String> = ["drums", "percussion", "click", "timecode"]

    static func includesByDefault(displayName: String, groupName: String?) -> Bool {
        if displayName.caseInsensitiveCompare(ClickTrackFileGenerator.trackDisplayName) == .orderedSame {
            return false
        }
        let group = groupName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return !excludedGroupNames.contains(group)
    }

    /// Songs that have never been transposed start from the group defaults.
    /// A saved selection is restored after the user has applied a key change.
    static func initialIncludedIDs(in song: Song) -> Set<UUID> {
        let hasSavedSelection = song.transposeSemitones != 0
            || song.sortedTracks.contains { !$0.includeInKeyChange }
        if hasSavedSelection {
            return Set(song.sortedTracks.filter(\.includeInKeyChange).map(\.id))
        }
        return Set(
            song.sortedTracks.filter { track in
                includesByDefault(displayName: track.displayName, groupName: track.group?.name)
            }.map(\.id)
        )
    }
}
