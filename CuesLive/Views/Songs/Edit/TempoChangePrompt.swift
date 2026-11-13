import SwiftUI

/// Asks which tempo a double-click on the tempo lane should use, and which tracks should
/// speed up or slow down with it. Tracks start locked, so their audio stays on the beat.
struct TempoChangePrompt: View {
    let measure: Int
    let currentBPM: Double
    let tracks: [AudioTrack]
    let onCancel: () -> Void
    let onChange: (_ bpm: Double, _ lockedTrackIDs: Set<UUID>) -> Void

    @State private var bpmText: String
    @State private var lockedTrackIDs: Set<UUID>
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
        _lockedTrackIDs = State(initialValue: Set(tracks.map(\.id)))
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
                        .disabled(enteredBPM == nil)
                }
            }
        }
        .standardDialogToolbar()
        .frame(minWidth: 380, minHeight: tracks.isEmpty ? 200 : 460)
        .onAppear { isFieldFocused = true }
    }

    private var tempoSection: some View {
        Section {
            LabeledContent("Tempo") {
                HStack(spacing: AppSpacing.xs) {
                    TextField("Tempo", text: $bpmText, prompt: Text(String(format: "%.1f", currentBPM)))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 80)
                        .focused($isFieldFocused)
                        .onSubmit(submit)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Text("BPM")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(tempoFooter)
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
                Text("Lock to Tempo")
                Spacer()
                Button(allLocked ? "Unlock All" : "Lock All", action: toggleAll)
                    .buttonStyle(.borderless)
                    .font(.callout)
            }
        } footer: {
            Text("Locked tracks speed up or slow down to stay on the beat. Unlocked tracks keep playing as recorded.")
        }
    }

    private var tempoFooter: String {
        let range = TempoChange.validBPMRange
        return "Starts at measure \(measure). Enter a tempo from \(Int(range.lowerBound)) to \(Int(range.upperBound)) BPM."
    }

    /// The typed tempo, or `nil` when it isn't a number within the valid BPM range.
    private var enteredBPM: Double? {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized), TempoChange.validBPMRange.contains(value) else { return nil }
        return value
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
        guard let bpm = enteredBPM else { return }
        onChange(bpm, lockedTrackIDs)
    }
}
