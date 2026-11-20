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
