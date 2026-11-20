import Foundation
import SwiftData

@Model
final class TrackGroup {
    var id: UUID
    var name: String
    var sortOrder: Int
    var volume: Double = 1.0
    var isMuted: Bool = false
    var isSoloed: Bool = false
    /// Key into `TrackGroupPalette` selectable swatches (e.g. "red", "blue").
    var paletteKey: String = "gray"
    /// Comma-separated track-name keywords used for auto-assign.
    var nameKeywords: String = ""

    init(
        name: String,
        sortOrder: Int,
        volume: Double = 1.0,
        isMuted: Bool = false,
        paletteKey: String = "gray",
        nameKeywords: String = ""
    ) {
        id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.volume = volume
        self.isMuted = isMuted
        self.paletteKey = paletteKey
        self.nameKeywords = nameKeywords
    }

    var keywordList: [String] {
        nameKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func setKeywordList(_ keywords: [String]) {
        nameKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
