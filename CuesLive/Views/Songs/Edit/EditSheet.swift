import Foundation

/// The sheet the song editor is presenting. SwiftUI shows one sheet per view at a time,
/// so a single optional value replaces a flag per sheet that could disagree.
enum EditSheet: Identifiable {
    case groupEditor
    case sectionNames
    case changeKey
    case addTrackType
    case midiDevicePicker
    case midiDeviceEditor(MIDIDevice)
    case tempoChange(TempoLanePrompt)
    case timeSignatureChange(TimeSignatureLanePrompt)
    case clipGain(ClipGainPromptRequest)

    var id: String {
        switch self {
        case .groupEditor:
            "groupEditor"
        case .sectionNames:
            "sectionNames"
        case .changeKey:
            "changeKey"
        case .addTrackType:
            "addTrackType"
        case .midiDevicePicker:
            "midiDevicePicker"
        case .midiDeviceEditor(let device):
            "midiDeviceEditor-\(device.id)"
        case .tempoChange(let prompt):
            "tempoChange-\(prompt.id)"
        case .timeSignatureChange(let prompt):
            "timeSignatureChange-\(prompt.id)"
        case .clipGain(let prompt):
            "clipGain-\(prompt.id)"
        }
    }
}
