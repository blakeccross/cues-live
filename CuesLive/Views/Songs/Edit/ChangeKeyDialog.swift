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
    @State private var isApplying = false
    @State private var progressText = ""
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
                    .disabled(isApplying)
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
                .disabled(isApplying)
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
                    .disabled(isApplying)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Apply") {
                            apply()
                        }
                        .disabled(!canApply)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isApplying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(progressText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 460)
        .interactiveDismissDisabled(isApplying)
        .onAppear {
            semitones = song.transposeSemitones
            includedTrackIDs = KeyChangeTrackSelection.initialIncludedIDs(in: song)
        }
        .alert("Pitch Shift Failed", isPresented: Binding(
            get: { applyError != nil },
            set: { if !$0 { applyError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(applyError ?? "")
        }
    }

    private var canApply: Bool {
        !isApplying && !song.sortedTracks.isEmpty
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

        isApplying = true
        viewModel.stop()
        Task {
            do {
                try await viewModel.applyKeyChange(context: modelContext) { progress in
                    if progress.total == 0 {
                        progressText = "Restoring original key"
                    } else if progress.trackName.isEmpty {
                        progressText = "Finishing"
                    } else {
                        progressText = "Pitching \(progress.trackName) (\(progress.completed + 1) of \(progress.total))"
                    }
                }
                let after = captureSnapshot()
                registerUndo("Change Key", before, after)
                dismiss()
            } catch {
                song.transposeSemitones = previousSemitones
                for track in song.sortedTracks {
                    track.includeInKeyChange = previousInclusion[track.id] ?? true
                }
                applyError = error.localizedDescription
                isApplying = false
            }
        }
    }
}
