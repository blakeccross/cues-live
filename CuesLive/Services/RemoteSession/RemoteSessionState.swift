import Foundation

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
    var cuedSectionID: UUID?
    var cueFireTime: TimeInterval?
    var isLooping: Bool
    var activeLoopSectionID: UUID?
    var manualLoopSectionID: UUID?
    var isFadedOut: Bool
    var isFading: Bool
    var groupVolumes: [String: Double]
    var mutedGroupIDs: [UUID]
    var soloedGroupIDs: [UUID] = []
    var ungroupedVolume: Double
    var ungroupedIsMuted: Bool
    var ungroupedIsSoloed = false

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

extension RemoteSessionState {
    /// Older hosts don't send solo state; everything else is required.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        currentSongID = try container.decodeIfPresent(UUID.self, forKey: .currentSongID)
        isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        isAudiblePlaying = try container.decode(Bool.self, forKey: .isAudiblePlaying)
        isLoaded = try container.decode(Bool.self, forKey: .isLoaded)
        isLoadingSong = try container.decode(Bool.self, forKey: .isLoadingSong)
        loadError = try container.decodeIfPresent(String.self, forKey: .loadError)
        currentTime = try container.decode(TimeInterval.self, forKey: .currentTime)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        cuedSectionID = try container.decodeIfPresent(UUID.self, forKey: .cuedSectionID)
        cueFireTime = try container.decodeIfPresent(TimeInterval.self, forKey: .cueFireTime)
        isLooping = try container.decode(Bool.self, forKey: .isLooping)
        activeLoopSectionID = try container.decodeIfPresent(UUID.self, forKey: .activeLoopSectionID)
        manualLoopSectionID = try container.decodeIfPresent(UUID.self, forKey: .manualLoopSectionID)
        isFadedOut = try container.decode(Bool.self, forKey: .isFadedOut)
        isFading = try container.decode(Bool.self, forKey: .isFading)
        groupVolumes = try container.decode([String: Double].self, forKey: .groupVolumes)
        mutedGroupIDs = try container.decode([UUID].self, forKey: .mutedGroupIDs)
        soloedGroupIDs = try container.decodeIfPresent([UUID].self, forKey: .soloedGroupIDs) ?? []
        ungroupedVolume = try container.decode(Double.self, forKey: .ungroupedVolume)
        ungroupedIsMuted = try container.decode(Bool.self, forKey: .ungroupedIsMuted)
        ungroupedIsSoloed = try container.decodeIfPresent(Bool.self, forKey: .ungroupedIsSoloed) ?? false
    }
}
