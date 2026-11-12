import SwiftUI

/// Asks which tempo a double-click on the tempo lane should use, and which tracks should
/// speed up or slow down with it. Tracks start unlocked, so their audio stays as it is.
struct TempoChangePrompt: View {
    let measure: Int
    let currentBPM: Double
    let tracks: [AudioTrack]
    let onCancel: () -> Void
    let onChange: (_ bpm: Double, _ lockedTrackIDs: Set<UUID>) -> Void

    @State private var bpmText: String
    @State private var lockedTrackIDs: Set<UUID> = []
    @FocusState private var isFieldFocused: Bool

    init(
        measure: Int,
        currentBPM: Double,
        tracks: [AudioTrack],
        onCancel: @escaping () -> Void,
        onChange: @escaping (_ bpm: Double, _ lockedTrackIDs: Set<UUID>) -> Void
    ) {
        self.measure = measure
        self.currentBPM = currentBPM
        self.tracks = tracks
        self.onCancel = onCancel
        self.onChange = onChange
        _bpmText = State(initialValue: String(format: "%.1f", currentBPM))
    }

    var body: some View {
        NavigationStack {
            Form {
                tempoSection
                if !tracks.isEmpty {
                    trackLockSection
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Change Tempo")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Change", action: submit)
                }
            }
        }
        .standardDialogToolbar()
        .frame(minWidth: 360, minHeight: tracks.isEmpty ? 160 : 420)
        .onAppear { isFieldFocused = true }
    }

    private var tempoSection: some View {
        Section {
            HStack(spacing: AppSpacing.xs) {
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($isFieldFocused)
                    .onSubmit(submit)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                Text("BPM")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("What tempo should measure \(measure) change to?")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trackLockSection: some View {
        Section {
            ForEach(tracks) { track in
                Toggle(isOn: lockBinding(for: track.id)) {
                    Text(track.displayName)
                    if let groupName = track.group?.name {
                        Text(groupName)
                    }
                }
            }
        } header: {
            HStack {
                Text("Lock Tracks to Tempo")
                Spacer()
                Button(allLocked ? "Unlock All" : "Lock All", action: toggleAll)
                    .buttonStyle(.borderless)
            }
        } footer: {
            Text("Locked tracks speed up or slow down to stay on the beat. Unlocked tracks keep playing as recorded while the song's tempo changes.")
        }
    }

    private var allLocked: Bool {
        tracks.allSatisfy { lockedTrackIDs.contains($0.id) }
    }

    private func toggleAll() {
        lockedTrackIDs = allLocked ? [] : Set(tracks.map(\.id))
    }

    private func lockBinding(for trackID: UUID) -> Binding<Bool> {
        Binding(
            get: { lockedTrackIDs.contains(trackID) },
            set: { isLocked in
                if isLocked {
                    lockedTrackIDs.insert(trackID)
                } else {
                    lockedTrackIDs.remove(trackID)
                }
            }
        )
    }

    private func submit() {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized) else { return }
        let clamped = min(
            max(value, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
        onChange(clamped, lockedTrackIDs)
    }
}
