import SwiftUI

extension EditView {
    @ViewBuilder
    func sheetContent(for sheet: EditSheet) -> some View {
        switch sheet {
        case .groupEditor:
            TrackGroupEditorView()
        case .changeKey:
            ChangeKeyDialog(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerSnapshotChange(_:before:after:)
            )
        case .addTrackType:
            AddTrackTypeSheet { kind in
                pendingAddTrackKind = kind
                activeSheet = nil
            }
        case .midiDevicePicker:
            MIDIDevicePickerView { device in
                createMIDITrack(for: device)
            }
        case .midiDeviceEditor(let device):
            midiDeviceEditor(for: device)
        case .renameSection(let section, let title):
            RenameSectionSheet(title: title, currentName: section.name) { newName in
                applySectionRename(newName, to: section)
            }
        case .tempoChange(let prompt):
            TempoChangePrompt(
                measure: prompt.measure,
                currentBPM: prompt.bpm,
                tracks: song.sortedTracks,
                onCancel: { activeSheet = nil },
                onChange: { bpm, lockedTrackIDs in
                    applyTempoChange(prompt: prompt, bpm: bpm, lockedTrackIDs: lockedTrackIDs)
                }
            )
        case .timeSignatureChange(let prompt):
            TimeSignatureChangePrompt(
                measure: prompt.measure,
                numerator: prompt.numerator,
                denominator: prompt.denominator,
                onCancel: { activeSheet = nil },
                onChange: { numerator, denominator in
                    applyTimeSignatureChange(prompt: prompt, numerator: numerator, denominator: denominator)
                }
            )
        case .clipGain(let prompt):
            ClipGainPrompt(
                initialDecibels: prompt.decibels,
                clipCount: prompt.clipCount,
                onCancel: { activeSheet = nil },
                onApply: applyClipGain
            )
        }
    }

    private func midiDeviceEditor(for device: MIDIDevice) -> some View {
        NavigationStack {
            MIDIDeviceEditorView(device: device) { _ in
                commitMIDIConfig()
            }
        }
        // `.sheet(item:)` alone can still let the NavigationStack-wrapped
        // content reuse its previous `@State` (destination, channel,
        // commands) instead of reinitializing from `device`, since the
        // NavigationStack's own identity sits between the sheet and the
        // editor. Keying explicitly by `device.id` forces a genuinely new
        // view — and fresh `@State` — every time a different device (or
        // the same one, after a prior edit) is opened.
        .id(device.id)
        .formSheetFrame(minWidth: 420, minHeight: 460)
    }
}
