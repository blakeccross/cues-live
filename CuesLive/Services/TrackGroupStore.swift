import Foundation
import SwiftData

enum TrackGroupStore {
    static let defaultNames = [
        "Drums",
        "Percussion",
        "Bass",
        "EG",
        "AG",
        "Keys",
        "Synth",
        "LV",
        "BGV",
        "Strings",
        "Other",
        "Click",
        "Cues",
        "Timecode",
    ]

    static func ensureDefaults(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<TrackGroup>())) ?? []
        var groupsByLowercasedName: [String: TrackGroup] = [:]
        for group in existing {
            let key = group.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            if groupsByLowercasedName[key] == nil {
                groupsByLowercasedName[key] = group
            }
        }

        var didChange = false

        for (index, name) in defaultNames.enumerated() {
            let key = name.lowercased()
            let paletteKey = defaultPaletteKey(forGroupName: name)
            let keywords = defaultKeywords(forGroupName: name)
            if let existingGroup = groupsByLowercasedName[key] {
                if existingGroup.sortOrder != index {
                    existingGroup.sortOrder = index
                    didChange = true
                }
                if existingGroup.name != name {
                    existingGroup.name = name
                    didChange = true
                }
                if existingGroup.paletteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    existingGroup.paletteKey = paletteKey
                    didChange = true
                }
                if mergeMissingDefaultKeywords(keywords, into: existingGroup) {
                    didChange = true
                }
            } else {
                let group = TrackGroup(
                    name: name,
                    sortOrder: index,
                    paletteKey: paletteKey,
                    nameKeywords: keywords.joined(separator: ", ")
                )
                context.insert(group)
                groupsByLowercasedName[key] = group
                didChange = true
            }
        }

        let defaultKeys = Set(defaultNames.map { $0.lowercased() })
        let customGroups = existing
            .filter {
                let key = $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return !key.isEmpty && !defaultKeys.contains(key)
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }

        var nextCustomOrder = defaultNames.count
        for group in customGroups {
            if group.sortOrder != nextCustomOrder {
                group.sortOrder = nextCustomOrder
                didChange = true
            }
            if group.paletteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                group.paletteKey = "gray"
                didChange = true
            }
            nextCustomOrder += 1
        }

        if didChange {
            try? context.save()
        }
    }

    @discardableResult
    private static func mergeMissingDefaultKeywords(_ keywords: [String], into group: TrackGroup) -> Bool {
        guard !keywords.isEmpty else { return false }
        let existing = group.keywordList
        let existingLowercased = Set(existing.map { $0.lowercased() })
        let missing = keywords.filter { !existingLowercased.contains($0.lowercased()) }
        guard !missing.isEmpty else { return false }
        group.setKeywordList(existing + missing)
        return true
    }

    static func sortedGroups(from context: ModelContext) -> [TrackGroup] {
        let descriptor = FetchDescriptor<TrackGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func isNameAvailable(
        _ name: String,
        excluding groupID: UUID?,
        in context: ModelContext
    ) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let groups = (try? context.fetch(FetchDescriptor<TrackGroup>())) ?? []
        return !groups.contains { group in
            group.id != groupID
                && group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func addGroup(named name: String, in context: ModelContext) -> TrackGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNameAvailable(trimmed, excluding: nil, in: context) else { return nil }

        let groups = sortedGroups(from: context)
        let nextSortOrder = (groups.map(\.sortOrder).max() ?? -1) + 1
        let group = TrackGroup(
            name: trimmed,
            sortOrder: nextSortOrder,
            paletteKey: "gray"
        )
        context.insert(group)
        try? context.save()
        return group
    }

    static func findOrCreateGroup(named name: String, in context: ModelContext) -> TrackGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let groups = sortedGroups(from: context)
        if let existing = groups.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return existing
        }
        return addGroup(named: trimmed, in: context)
    }

    static func delete(_ group: TrackGroup, in context: ModelContext) {
        let groupID = group.id
        let tracks = (try? context.fetch(FetchDescriptor<AudioTrack>())) ?? []
        for track in tracks where track.group?.id == groupID {
            track.group = nil
        }
        context.delete(group)
        try? context.save()
    }

    static func guessGroup(for trackName: String, from groups: [TrackGroup]) -> TrackGroup? {
        let normalized = trackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let tokens = tokenize(normalized)
        let candidates = groups.sorted {
            if $0.name.count != $1.name.count {
                return $0.name.count > $1.name.count
            }
            return $0.sortOrder < $1.sortOrder
        }

        for group in candidates {
            let groupName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !groupName.isEmpty else { continue }

            if matches(term: groupName, in: normalized, tokens: tokens) {
                return group
            }
        }

        let aliasEntries: [(keyword: String, group: TrackGroup)] = groups.flatMap { group in
            group.keywordList.map { (keyword: $0, group: group) }
        }
        .sorted { $0.keyword.count > $1.keyword.count }

        for entry in aliasEntries {
            guard matches(term: entry.keyword, in: normalized, tokens: tokens) else { continue }
            return entry.group
        }

        return nil
    }

    @discardableResult
    static func autoAssignGroups(
        for song: Song,
        in context: ModelContext
    ) -> Int {
        ensureDefaults(in: context)
        let groups = sortedGroups(from: context)
        let assignedCount = autoAssignGroups(for: song.sortedTracks, groups: groups, in: context)
        reorderTracksByGroup(in: song, context: context)
        return assignedCount
    }

    @discardableResult
    static func autoAssignGroups(
        for tracks: [AudioTrack],
        groups: [TrackGroup],
        in context: ModelContext
    ) -> Int {
        var assignedCount = 0

        for track in tracks {
            guard let group = guessGroup(for: track.displayName, from: groups) else { continue }
            track.group = group
            assignedCount += 1
        }

        if assignedCount > 0 {
            try? context.save()
        }

        return assignedCount
    }

    static func reorderTracksByGroup(in song: Song, context: ModelContext) {
        let tracks = song.sortedTracks
        guard !tracks.isEmpty else { return }

        let sorted = tracks.sorted { lhs, rhs in
            let lhsOrder = lhs.group?.sortOrder ?? Int.max
            let rhsOrder = rhs.group?.sortOrder ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        var didChange = false
        for (index, track) in sorted.enumerated() where track.sortOrder != index {
            track.sortOrder = index
            didChange = true
        }

        if didChange {
            try? context.save()
        }
    }

    static func defaultPaletteKey(forGroupName name: String) -> String {
        switch name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "drums":
            return "red"
        case "percussion":
            return "orange"
        case "bass", "eg", "ag":
            return "blue"
        case "keys", "synth":
            return "green"
        case "lv", "bgv":
            return "purple"
        case "strings":
            return "brown"
        case "click":
            return "darkGray"
        case "cues":
            return "white"
        case "timecode":
            return "darkGray"
        default:
            return "gray"
        }
    }

    static func defaultKeywords(forGroupName name: String) -> [String] {
        switch name.lowercased() {
        case "drums":
            return [
                "kick in", "kick out", "kick", "snare top", "snare bot", "snare", "snr",
                "rack tom", "floor tom", "rack", "floor", "flr", "tom", "toms",
                "hat", "hihat", "hi-hat", "overhead", "room", "trig", "drum", "drums",
                "knee"
            ]
        case "bass":
            return ["bass", "bas", "sub", "subwoofer", "di bass"]
        case "lv":
            return [
                "lead vocal", "lead vox", "vocal", "vox", "verse vox",
                "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8",
                "announce", "announcer"
            ]
        case "percussion":
            return [
                "cymbals", "cymbal", "crash", "ride", "shaker", "tambourine",
                "conga", "bongo", "maraca", "perc", "percussion", "cowbell",
                "clap", "hi-hat", "hihat", "loop", "fx"
            ]
        case "keys":
            return ["piano", "organ", "org", "rhodes", "wurli", "keyboard", "keys", "glockenspiel", "glock"]
        case "synth":
            return ["synth", "synthesizer", "pad", "pads", "arp", "lead synth"]
        case "bgv":
            return [
                "vocoder", "backing", "harmony", "choir",
                "soprano", "alto", "tenor", "baritone", "mezzo", "bgv", "gangs"
            ]
        case "eg":
            return [
                "electric guitar", "electric gtr", "electric guitars",
                "lead guitar", "rhythm guitar",
                "clean guitar", "clean gtr",
                "guitar", "guitars", "gtr", "egtr"
            ]
        case "ag":
            return [
                "acoustic guitar", "acoustic gtr", "ac guitar", "ac gtr",
                "acoustic", "agtr", "aco"
            ]
        case "strings":
            return ["strings", "violin", "viola", "cello", "cellos", "orchestra"]
        case "other":
            return ["crowd", "audience", "ambience", "ambient", "talkback", "sfx"]
        case "click":
            return ["click track", "click", "metronome"]
        case "cues":
            return ["cues", "cue"]
        case "timecode":
            return ["timecode", "ltc", "smpte"]
        default:
            return []
        }
    }

    private static func tokenize(_ name: String) -> [String] {
        name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
    }

    private static func matches(term: String, in trackName: String, tokens: [String]) -> Bool {
        let termLower = term.lowercased()
        if tokens.contains(termLower) {
            return true
        }

        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: termLower))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }

        let range = NSRange(trackName.startIndex..., in: trackName)
        return regex.firstMatch(in: trackName, options: [], range: range) != nil
    }
}
