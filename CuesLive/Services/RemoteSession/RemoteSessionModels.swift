import Foundation
import Network

enum RemoteSessionBonjour {
    static let serviceType = "_cueslive._tcp"
    static let protocolVersion = 1
    static let pinLength = 4
    /// Bonjour TXT key for a stable per-install ID used to hide this device from its own browse list.
    static let instanceIDTXTKey = "iid"
}

struct RemoteSessionPeer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let endpoint: NWEndpointBox
}

/// `NWEndpoint` is not Hashable in a UI-friendly way; wrap for discovery lists.
struct NWEndpointBox: Hashable, @unchecked Sendable {
    let endpoint: NWEndpoint

    static func == (lhs: NWEndpointBox, rhs: NWEndpointBox) -> Bool {
        String(describing: lhs.endpoint) == String(describing: rhs.endpoint)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: endpoint))
    }
}

struct RemoteArrangementSectionDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var slotID: UUID
    var markerID: UUID
    var name: String
    var sourceStartSeconds: TimeInterval
    var sourceEndSeconds: TimeInterval
    var timelineStartSeconds: TimeInterval
    var timelineEndSeconds: TimeInterval
    var columnStartSeconds: TimeInterval
    var columnEndSeconds: TimeInterval

    init(_ section: ArrangementDisplaySection) {
        id = section.id
        slotID = section.slotID
        markerID = section.markerID
        name = section.name
        sourceStartSeconds = section.sourceStartSeconds
        sourceEndSeconds = section.sourceEndSeconds
        timelineStartSeconds = section.timelineStartSeconds
        timelineEndSeconds = section.timelineEndSeconds
        columnStartSeconds = section.columnStartSeconds
        columnEndSeconds = section.columnEndSeconds
    }

    var asDisplaySection: ArrangementDisplaySection {
        ArrangementDisplaySection(
            id: id,
            slotID: slotID,
            markerID: markerID,
            name: name,
            sourceStartSeconds: sourceStartSeconds,
            sourceEndSeconds: sourceEndSeconds,
            timelineStartSeconds: timelineStartSeconds,
            timelineEndSeconds: timelineEndSeconds,
            columnStartSeconds: columnStartSeconds,
            columnEndSeconds: columnEndSeconds
        )
    }
}

extension RemoteSongDTO {
    var asWaveformSnapshot: LiveSongWaveformSnapshot {
        let tempo = tempoChanges.isEmpty
            ? [TempoChange(startMeasure: 1, bpm: TempoChange.defaultBPM)]
            : tempoChanges
        let signatures = timeSignatureChanges.isEmpty
            ? [
                TimeSignatureChange(
                    numerator: TimeSignatureChange.defaultNumerator,
                    denominator: TimeSignatureChange.defaultDenominator,
                    startMeasure: 1
                )
            ]
            : timeSignatureChanges

        return LiveSongWaveformSnapshot(
            songID: id,
            songName: name,
            trackSources: [],
            fileDuration: fileDuration,
            timelineDuration: timelineDuration,
            sections: sections.map(\.asDisplaySection),
            peakSections: peakSections.map(\.asDisplaySection),
            loopSlotIDs: Set(loopSlotIDs),
            tempoChanges: tempo,
            timeSignatureChanges: signatures,
            showsMeasureGrid: showsMeasureGrid,
            precomputedSourcePeaks: peaks
        )
    }
}

extension RemoteSessionSnapshot {
    var timelineItems: [LiveSetlistTimelineItem] {
        var items: [LiveSetlistTimelineItem] = []
        let songEntries = entries.filter { $0.songID != nil && $0.playbackIndex != nil }

        for entry in entries {
            if let header = entry.headerTitle, entry.songID == nil {
                items.append(.header(scrollID: entry.id.uuidString, title: header))
                continue
            }
            guard let songID = entry.songID,
                  let playbackIndex = entry.playbackIndex else {
                continue
            }
            let hasNextSong = songEntries.contains { ($0.playbackIndex ?? -1) > playbackIndex }
            let transition = SetlistTransition(rawValue: entry.transition)
            items.append(
                .song(
                    songID: songID,
                    playbackIndex: playbackIndex,
                    transitionAfter: hasNextSong ? transition : nil
                )
            )
        }
        return items
    }

    func waveformSnapshot(forSongID songID: UUID) -> LiveSongWaveformSnapshot? {
        songs.first(where: { $0.id == songID })?.asWaveformSnapshot
    }
}

struct RemoteLibrarySongDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var bpm: Double?
    var trackCount: Int
    var createdAt: Date
}

struct RemoteSongDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var fileDuration: TimeInterval
    var timelineDuration: TimeInterval
    var key: String
    var sections: [RemoteArrangementSectionDTO]
    var peakSections: [RemoteArrangementSectionDTO]
    var loopSlotIDs: [UUID]
    var tempoChanges: [TempoChange]
    var timeSignatureChanges: [TimeSignatureChange]
    /// When false, remote clients hide measure ticks (host song has no set BPM).
    var showsMeasureGrid: Bool
    /// Downsampled summed peaks for remote waveform display (no media transfer).
    var peaks: [Float]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fileDuration
        case timelineDuration
        case key
        case sections
        case peakSections
        case loopSlotIDs
        case tempoChanges
        case timeSignatureChanges
        case showsMeasureGrid
        case peaks
    }

    init(
        id: UUID,
        name: String,
        fileDuration: TimeInterval,
        timelineDuration: TimeInterval,
        key: String,
        sections: [RemoteArrangementSectionDTO],
        peakSections: [RemoteArrangementSectionDTO],
        loopSlotIDs: [UUID],
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        showsMeasureGrid: Bool,
        peaks: [Float]
    ) {
        self.id = id
        self.name = name
        self.fileDuration = fileDuration
        self.timelineDuration = timelineDuration
        self.key = key
        self.sections = sections
        self.peakSections = peakSections
        self.loopSlotIDs = loopSlotIDs
        self.tempoChanges = tempoChanges
        self.timeSignatureChanges = timeSignatureChanges
        self.showsMeasureGrid = showsMeasureGrid
        self.peaks = peaks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        fileDuration = try container.decode(TimeInterval.self, forKey: .fileDuration)
        timelineDuration = try container.decode(TimeInterval.self, forKey: .timelineDuration)
        key = try container.decode(String.self, forKey: .key)
        sections = try container.decode([RemoteArrangementSectionDTO].self, forKey: .sections)
        peakSections = try container.decodeIfPresent([RemoteArrangementSectionDTO].self, forKey: .peakSections) ?? sections
        loopSlotIDs = try container.decode([UUID].self, forKey: .loopSlotIDs)
        tempoChanges = try container.decode([TempoChange].self, forKey: .tempoChanges)
        timeSignatureChanges = try container.decode([TimeSignatureChange].self, forKey: .timeSignatureChanges)
        // Older hosts omit this; keep prior behavior (show grid when tempo map exists).
        showsMeasureGrid = try container.decodeIfPresent(Bool.self, forKey: .showsMeasureGrid)
            ?? !tempoChanges.isEmpty
        peaks = try container.decodeIfPresent([Float].self, forKey: .peaks) ?? []
    }
}

struct RemoteSetlistEntryDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var sortOrder: Int
    var headerTitle: String?
    var songID: UUID?
    var transition: String
    var playbackIndex: Int?
}

struct RemoteGroupDTO: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var volume: Double
    var isMuted: Bool
    var isMixable: Bool
    /// Key into `TrackGroupPalette` (e.g. "red", "blue"). Defaults for older hosts.
    var paletteKey: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sortOrder
        case volume
        case isMuted
        case isMixable
        case paletteKey
    }

    init(
        id: UUID,
        name: String,
        sortOrder: Int,
        volume: Double,
        isMuted: Bool,
        isMixable: Bool,
        paletteKey: String = "gray"
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.volume = volume
        self.isMuted = isMuted
        self.isMixable = isMixable
        self.paletteKey = paletteKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        volume = try container.decode(Double.self, forKey: .volume)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isMixable = try container.decode(Bool.self, forKey: .isMixable)
        paletteKey = try container.decodeIfPresent(String.self, forKey: .paletteKey) ?? "gray"
    }
}

struct RemoteSessionSnapshot: Codable, Sendable {
    var protocolVersion: Int
    var hostDisplayName: String
    var setlistID: UUID
    var setlistName: String
    var entries: [RemoteSetlistEntryDTO]
    var songs: [RemoteSongDTO]
    /// Full host song library (for remote browse / add-to-setlist). Not limited to setlist songs.
    var librarySongs: [RemoteLibrarySongDTO]
    var groups: [RemoteGroupDTO]
    var state: RemoteSessionState

    enum CodingKeys: String, CodingKey {
        case protocolVersion
        case hostDisplayName
        case setlistID
        case setlistName
        case entries
        case songs
        case librarySongs
        case groups
        case state
    }

    init(
        protocolVersion: Int,
        hostDisplayName: String,
        setlistID: UUID,
        setlistName: String,
        entries: [RemoteSetlistEntryDTO],
        songs: [RemoteSongDTO],
        librarySongs: [RemoteLibrarySongDTO],
        groups: [RemoteGroupDTO],
        state: RemoteSessionState
    ) {
        self.protocolVersion = protocolVersion
        self.hostDisplayName = hostDisplayName
        self.setlistID = setlistID
        self.setlistName = setlistName
        self.entries = entries
        self.songs = songs
        self.librarySongs = librarySongs
        self.groups = groups
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        hostDisplayName = try container.decode(String.self, forKey: .hostDisplayName)
        setlistID = try container.decode(UUID.self, forKey: .setlistID)
        setlistName = try container.decode(String.self, forKey: .setlistName)
        entries = try container.decode([RemoteSetlistEntryDTO].self, forKey: .entries)
        songs = try container.decode([RemoteSongDTO].self, forKey: .songs)
        librarySongs = try container.decodeIfPresent([RemoteLibrarySongDTO].self, forKey: .librarySongs) ?? []
        groups = try container.decode([RemoteGroupDTO].self, forKey: .groups)
        state = try container.decode(RemoteSessionState.self, forKey: .state)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(hostDisplayName, forKey: .hostDisplayName)
        try container.encode(setlistID, forKey: .setlistID)
        try container.encode(setlistName, forKey: .setlistName)
        try container.encode(entries, forKey: .entries)
        try container.encode(songs, forKey: .songs)
        try container.encode(librarySongs, forKey: .librarySongs)
        try container.encode(groups, forKey: .groups)
        try container.encode(state, forKey: .state)
    }
}

struct RemoteSessionState: Codable, Hashable, Sendable {
    var currentIndex: Int
    var currentSongID: UUID?
    var isPlaying: Bool
    var isAudiblePlaying: Bool
    var isLoaded: Bool
    var isLoadingSong: Bool
    var loadError: String?
    var currentTime: TimeInterval
    var duration: TimeInterval
    var bpmText: String
    var meterText: String
    var keyText: String
    var positionText: String
    var cuedSectionID: UUID?
    var cueFireTime: TimeInterval?
    var isLooping: Bool
    var activeLoopSectionID: UUID?
    var manualLoopSectionID: UUID?
    var isFadedOut: Bool
    var isFading: Bool
    var groupVolumes: [String: Double]
    var mutedGroupIDs: [UUID]
    var ungroupedVolume: Double
    var ungroupedIsMuted: Bool

    static let empty = RemoteSessionState(
        currentIndex: 0,
        currentSongID: nil,
        isPlaying: false,
        isAudiblePlaying: false,
        isLoaded: false,
        isLoadingSong: false,
        loadError: nil,
        currentTime: 0,
        duration: 0,
        bpmText: "—",
        meterText: "—",
        keyText: "—",
        positionText: "0:00",
        cuedSectionID: nil,
        cueFireTime: nil,
        isLooping: false,
        activeLoopSectionID: nil,
        manualLoopSectionID: nil,
        isFadedOut: false,
        isFading: false,
        groupVolumes: [:],
        mutedGroupIDs: [],
        ungroupedVolume: 1,
        ungroupedIsMuted: false
    )
}

enum RemoteSessionCommand: Codable, Sendable {
    case play
    case pause
    case stop
    case seek(TimeInterval)
    case nextSong(autoPlay: Bool)
    case previousSong(autoPlay: Bool)
    case goToSong(index: Int, autoPlay: Bool)
    case setGroupVolume(groupID: UUID?, volume: Double, provisional: Bool)
    case setGroupMuted(groupID: UUID?, muted: Bool)
    case toggleFade
    case clearFade
    case cueSection(sectionID: UUID)
    case cancelCue
    case snapToCuedSection
    case toggleSectionLoop
    case beginManualLoop(sectionID: UUID)
    case endLoop
    /// Removes a setlist entry (song or header) by remote stable entry ID.
    case removeSetlistEntry(entryID: UUID)
    /// Moves a setlist entry to `toIndex` in the current sorted entry list.
    case moveSetlistEntry(entryID: UUID, toIndex: Int)
    /// Adds a host-library song to the live setlist (`atIndex` nil appends).
    case addSongToSetlist(songID: UUID, atIndex: Int?)
    /// Inserts a setlist header (`atIndex` nil appends).
    case addSetlistHeader(title: String, atIndex: Int?)
}

enum RemoteSessionMessage: Codable, Sendable {
    case hello(protocolVersion: Int, displayName: String)
    case auth(pin: String)
    case authResult(success: Bool, message: String?)
    case snapshot(RemoteSessionSnapshot)
    case state(RemoteSessionState)
    case command(RemoteSessionCommand)
    case ping
    case pong
    case error(String)
}
