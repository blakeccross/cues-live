import Foundation

/// Live-performance actions that can be bound to a key or MIDI note.
enum MappableLiveAction: Codable, Hashable, Identifiable, Sendable {
    case stop
    case playPause
    case fade
    case loop
    case goToSong(Int)
    case goToSection(songIndex: Int, sectionIndex: Int)

    static let transportActions: [MappableLiveAction] = [
        .stop,
        .playPause,
        .fade,
        .loop,
    ]

    var id: String {
        switch self {
        case .stop: "stop"
        case .playPause: "playPause"
        case .fade: "fade"
        case .loop: "loop"
        case .goToSong(let index): "goToSong.\(index)"
        case .goToSection(let songIndex, let sectionIndex): "goToSection.\(songIndex).\(sectionIndex)"
        }
    }

    var title: String {
        switch self {
        case .stop: "Stop"
        case .playPause: "Play"
        case .fade: "Fade"
        case .loop: "Loop"
        case .goToSong(let index): "Song \(index + 1)"
        case .goToSection(let songIndex, let sectionIndex):
            "Song \(songIndex + 1) · Section \(sectionIndex + 1)"
        }
    }

    var systemImage: String {
        switch self {
        case .stop: "stop.fill"
        case .playPause: "play.fill"
        case .fade: "righttriangle.fill"
        case .loop: "repeat"
        case .goToSong: "music.note"
        case .goToSection: "flag"
        }
    }

    var sortOrder: Int {
        switch self {
        case .stop: 0
        case .playPause: 1
        case .fade: 2
        case .loop: 3
        case .goToSong(let index): 100 + index
        case .goToSection(let songIndex, let sectionIndex): 10_000 + songIndex * 1_000 + sectionIndex
        }
    }

    var songIndex: Int? {
        if case .goToSong(let index) = self {
            return index
        }
        return nil
    }

    var sectionTarget: (songIndex: Int, sectionIndex: Int)? {
        if case .goToSection(let songIndex, let sectionIndex) = self {
            return (songIndex, sectionIndex)
        }
        return nil
    }
}
