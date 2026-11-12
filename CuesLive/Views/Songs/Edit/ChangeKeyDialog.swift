import SwiftData
import SwiftUI

struct ChangeKeyDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void

    @State private var semitones = 0
    @State private var includedTrackIDs: Set<UUID> = []
    @State private var applyError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $semitones, in: -12...12) {
                        HStack {
                            Text("Transpose")
                            Spacer()
                            Text(semitoneLabel)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } footer: {
                    Text(transposeFooter)
                }

                Section {
                    if song.sortedTracks.isEmpty {
                        ContentUnavailableView(
                            "No Tracks",
                            systemImage: "waveform",
                            description: Text("Import stems before changing key.")
                        )
                    } else {
                        ForEach(song.sortedTracks) { track in
                            Toggle(isOn: inclusionBinding(for: track.id)) {
                                Text(track.displayName)
                                if let groupName = track.group?.name {
                                    Text(groupName)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tracks")
                } footer: {
                    Text("Drums, percussion, click, and timecode stay at the original pitch unless you turn them on.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Change Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        apply()
                    }
                    .disabled(!canApply)
                }
            }
        }
        .standardDialogToolbar()
        .frame(minWidth: 380, minHeight: 460)
        .onAppear {
            semitones = song.transposeSemitones
            includedTrackIDs = KeyChangeTrackSelection.initialIncludedIDs(in: song)
        }
        .alert("Key Change Failed", isPresented: Binding(
            get: { applyError != nil },
            set: { if !$0 { applyError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyError ?? "")
        }
    }

    private var canApply: Bool {
        !song.sortedTracks.isEmpty
    }

    private var transposeFooter: String {
        if let keyChangeLabel {
            return "\(keyChangeLabel). Tempo stays the same."
        }
        return "Tempo stays the same."
    }

    private var semitoneLabel: String {
        switch semitones {
        case 0:
            return "Original"
        case 1:
            return "+1 semitone"
        case -1:
            return "-1 semitone"
        case let value where value > 0:
            return "+\(value) semitones"
        default:
            return "\(semitones) semitones"
        }
    }

    private var keyChangeLabel: String? {
        guard let raw = song.baseKeyRaw, let base = SongMusicalKey(rawValue: raw) else { return nil }
        let shifted = base.transposed(by: semitones)
        guard shifted != base else { return base.displayName }
        return "\(base.displayName) → \(shifted.displayName)"
    }

    private func inclusionBinding(for trackID: UUID) -> Binding<Bool> {
        Binding(
            get: { includedTrackIDs.contains(trackID) },
            set: { isIncluded in
                if isIncluded {
                    includedTrackIDs.insert(trackID)
                } else {
                    includedTrackIDs.remove(trackID)
                }
            }
        )
    }

    private func apply() {
        let before = captureSnapshot()
        let previousSemitones = song.transposeSemitones
        let previousInclusion = Dictionary(
            uniqueKeysWithValues: song.sortedTracks.map { ($0.id, $0.includeInKeyChange) }
        )
        song.transposeSemitones = semitones
        for track in song.sortedTracks {
            track.includeInKeyChange = includedTrackIDs.contains(track.id)
        }

        do {
            try viewModel.applyKeyChange(context: modelContext)
            registerUndo("Change Key", before, captureSnapshot())
            dismiss()
        } catch {
            song.transposeSemitones = previousSemitones
            for track in song.sortedTracks {
                track.includeInKeyChange = previousInclusion[track.id] ?? true
            }
            applyError = error.localizedDescription
        }
    }
}
