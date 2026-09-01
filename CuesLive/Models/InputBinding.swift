import Foundation

struct KeyBinding: Codable, Hashable, Sendable {
    /// macOS virtual key code when known.
    var keyCode: UInt16?
    /// Layout character, ignoring modifiers (e.g. `"a"`, `" "`).
    var character: String
    /// Human-readable key name without modifiers (`"A"`, `"Space"`).
    var keyName: String
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    var displayName: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyName)
        return parts.joined()
    }

    var isEscape: Bool {
        keyCode == 53 || character == "\u{1b}" || keyName == "Escape"
    }

    var isReserved: Bool {
        isEscape || keyCode == 48 || keyName == "Tab"
    }

    /// Unmodified key binding with a known macOS virtual key code.
    static func unmodified(keyCode: UInt16, character: String, keyName: String) -> KeyBinding {
        KeyBinding(
            keyCode: keyCode,
            character: character,
            keyName: keyName,
            command: false,
            shift: false,
            option: false,
            control: false
        )
    }

    func matches(_ other: KeyBinding) -> Bool {
        guard command == other.command,
              shift == other.shift,
              option == other.option,
              control == other.control else {
            return false
        }

        if let keyCode, let otherCode = other.keyCode {
            return keyCode == otherCode
        }

        return !character.isEmpty
            && character.caseInsensitiveCompare(other.character) == .orderedSame
    }
}

struct MIDINoteBinding: Codable, Hashable, Sendable {
    /// MIDI note number, 0–127.
    var note: Int
    /// MIDI channel, 1–16.
    var channel: Int
    /// Display-only source name captured at learn time.
    var sourceName: String?

    var displayName: String {
        let noteLabel = Self.noteDisplayName(note)
        if let sourceName, !sourceName.isEmpty {
            return "\(noteLabel) · Ch \(channel) · \(sourceName)"
        }
        return "\(noteLabel) · Ch \(channel)"
    }

    /// Short label for live mapping badges (`C4` or `C4·2` when not on channel 1).
    var compactDisplayName: String {
        let noteLabel = Self.noteDisplayName(note)
        if channel == 1 {
            return noteLabel
        }
        return "\(noteLabel)·\(channel)"
    }

    func matches(_ other: MIDINoteBinding) -> Bool {
        note == other.note && channel == other.channel
    }

    /// Scientific pitch: MIDI 60 = C4.
    static func noteDisplayName(_ note: Int) -> String {
        let clamped = max(0, min(127, note))
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let name = names[clamped % 12]
        let octave = (clamped / 12) - 1
        return "\(name)\(octave)"
    }
}

struct InputMapping: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var action: MappableLiveAction
    var key: KeyBinding?
    var midi: MIDINoteBinding?

    init(
        id: UUID = UUID(),
        action: MappableLiveAction,
        key: KeyBinding? = nil,
        midi: MIDINoteBinding? = nil
    ) {
        self.id = id
        self.action = action
        self.key = key
        self.midi = midi
    }

    var isEmpty: Bool {
        key == nil && midi == nil
    }
}
