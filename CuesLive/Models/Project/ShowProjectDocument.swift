import Foundation

struct ShowProjectEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var sortOrder: Int
    var transition: String
    var songProject: ProjectDocumentReference?
    var headerTitle: String?
    var headerTimeSeconds: TimeInterval?
    var overlap: OverlapTransitionConfig?

    init(
        id: UUID = UUID(),
        sortOrder: Int,
        transition: SetlistTransition = .continue,
        songProject: ProjectDocumentReference? = nil,
        headerTitle: String? = nil,
        headerTimeSeconds: TimeInterval? = nil,
        overlap: OverlapTransitionConfig? = nil
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.transition = transition.rawValue
        self.songProject = songProject
        self.headerTitle = headerTitle
        self.headerTimeSeconds = headerTimeSeconds
        self.overlap = overlap
    }

    var transitionValue: SetlistTransition {
        SetlistTransition(rawValue: transition) ?? .continue
    }

    var isHeader: Bool {
        songProject == nil && headerTitle != nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sortOrder
        case transition
        case songProject
        case headerTitle
        case headerTimeSeconds
        case overlap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        transition = try container.decode(String.self, forKey: .transition)
        songProject = try container.decodeIfPresent(ProjectDocumentReference.self, forKey: .songProject)
        headerTitle = try container.decodeIfPresent(String.self, forKey: .headerTitle)
        headerTimeSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .headerTimeSeconds)
        overlap = try container.decodeIfPresent(OverlapTransitionConfig.self, forKey: .overlap)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(transition, forKey: .transition)
        try container.encodeIfPresent(songProject, forKey: .songProject)
        try container.encodeIfPresent(headerTitle, forKey: .headerTitle)
        try container.encodeIfPresent(headerTimeSeconds, forKey: .headerTimeSeconds)
        try container.encodeIfPresent(overlap, forKey: .overlap)
    }
}

struct ShowProjectDocument: Codable, Identifiable {
    static let currentFormatVersion = 3

    var formatVersion: Int
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date
    var entries: [ShowProjectEntry]

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        modifiedAt: Date = Date(),
        lastOpenedAt: Date = Date(),
        entries: [ShowProjectEntry] = []
    ) {
        formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastOpenedAt = lastOpenedAt
        self.entries = entries
    }
}
