import SwiftUI

enum DocsSection: String, CaseIterable, Identifiable {
    case basics
    case live
    case setup
    case reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basics: "Basics"
        case .live: "Live Performance"
        case .setup: "Setup"
        case .reference: "Reference"
        }
    }

    var topics: [DocsTopic] {
        DocsTopic.allCases.filter { $0.section == self }
    }
}

enum DocsTopic: String, CaseIterable, Identifiable, Hashable {
    case gettingStarted
    case songsAndEditing
    case setlists
    case livePlayback
    case mapping
    case remoteSessions
    case audioOutputs
    case timecode
    case fileFormats
    case keyboardShortcuts
    case about

    var id: String { rawValue }

    var section: DocsSection {
        switch self {
        case .gettingStarted, .songsAndEditing, .setlists:
            .basics
        case .livePlayback, .mapping, .remoteSessions:
            .live
        case .audioOutputs, .timecode:
            .setup
        case .fileFormats, .keyboardShortcuts, .about:
            .reference
        }
    }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .songsAndEditing: "Songs & Editing"
        case .setlists: "Setlists"
        case .livePlayback: "Live Playback"
        case .mapping: "Key & MIDI Mapping"
        case .remoteSessions: "Remote Sessions"
        case .audioOutputs: "Audio & Outputs"
        case .timecode: "Timecode"
        case .fileFormats: "File Formats"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .songsAndEditing: "waveform"
        case .setlists: "list.bullet"
        case .livePlayback: "play.circle"
        case .mapping: "keyboard"
        case .remoteSessions: "antenna.radiowaves.left.and.right"
        case .audioOutputs: "speaker.wave.2"
        case .timecode: "timelapse"
        case .fileFormats: "doc"
        case .keyboardShortcuts: "command"
        case .about: "info.circle"
        }
    }

    static var visibleTopics: [DocsTopic] {
        allCases.filter { topic in
            #if os(macOS)
            return true
            #else
            return topic != .keyboardShortcuts
            #endif
        }
    }

    static func visibleTopics(in section: DocsSection) -> [DocsTopic] {
        visibleTopics.filter { $0.section == section }
    }
}

#if os(macOS)
enum DocsWindowID {
    static let value = "docs"
}
#endif
