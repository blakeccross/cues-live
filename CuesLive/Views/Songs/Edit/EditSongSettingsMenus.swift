import SwiftData
import SwiftUI

struct SongKeyEditorMenu: View {
    let baseKeyRaw: String?
    let onApply: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Key")
                .font(.headline)

            Text("Sets the song’s key.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                keyRow(title: "None", isSelected: baseKeyRaw == nil) {
                    onApply(nil)
                    dismiss()
                }

                ForEach(SongMusicalKey.chromaticOrder, id: \.self) { key in
                    Divider()
                    keyRow(title: key.displayName, isSelected: baseKeyRaw == key.rawValue) {
                        onApply(key.rawValue)
                        dismiss()
                    }
                }
            }
            .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(AppSpacing.md)
        .frame(minWidth: 180)
    }

    private func keyRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.monospaced())
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TimeSignatureEditorMenu: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var song: Song
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    let normalizedTimeSignatureChanges: [TimeSignatureChange]
    let onPersist: () -> Void

    @State private var numerator: Int
    @State private var denominator: Int

    private static let presets: [(numerator: Int, denominator: Int)] = [
        (4, 4), (3, 4), (2, 4), (6, 8), (5, 4), (7, 8), (12, 8)
    ]

    private static let denominators = [2, 4, 8, 16]

    init(
        song: Song,
        timeSignatureChanges: Binding<[TimeSignatureChange]>,
        normalizedTimeSignatureChanges: [TimeSignatureChange],
        onPersist: @escaping () -> Void
    ) {
        self.song = song
        _timeSignatureChanges = timeSignatureChanges
        self.normalizedTimeSignatureChanges = normalizedTimeSignatureChanges
        self.onPersist = onPersist
        let initial = normalizedTimeSignatureChanges.first
        _numerator = State(initialValue: initial?.numerator ?? song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator)
        _denominator = State(initialValue: initial?.denominator ?? song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Time Signature")
                .font(.headline)

            Text("Edits the measure 1 time signature marker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        applyTimeSignature(numerator: preset.numerator, denominator: preset.denominator)
                    } label: {
                        Text("\(preset.numerator)/\(preset.denominator)")
                            .font(.body.monospacedDigit().weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .appEditorToolbarPill()
                    .tint(isSelected(numerator: preset.numerator, denominator: preset.denominator) ? AppColors.accent : .secondary)
                }
            }

            Divider()

            HStack(spacing: 16) {
                Stepper(value: $numerator, in: 1...32) {
                    Text("Beats: \(numerator)")
                        .monospacedDigit()
                }
                .onChange(of: numerator) { _, newValue in
                    applyTimeSignature(numerator: newValue, denominator: denominator)
                }

                Picker("Beat value", selection: $denominator) {
                    ForEach(Self.denominators, id: \.self) { value in
                        Text("1/\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                .onChange(of: denominator) { _, newValue in
                    applyTimeSignature(numerator: numerator, denominator: newValue)
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
        .onChange(of: song.timeSignatureNumerator) { _, _ in
            syncFromSong()
        }
        .onChange(of: song.timeSignatureDenominator) { _, _ in
            syncFromSong()
        }
    }

    private func isSelected(numerator: Int, denominator: Int) -> Bool {
        self.numerator == numerator && self.denominator == denominator
    }

    private func syncFromSong() {
        let initial = normalizedTimeSignatureChanges.first
        numerator = initial?.numerator ?? song.timeSignatureNumerator ?? MeasureTiming.defaultNumerator
        denominator = initial?.denominator ?? song.timeSignatureDenominator ?? MeasureTiming.defaultDenominator
    }

    private func applyTimeSignature(numerator: Int, denominator: Int) {
        guard (1...32).contains(numerator), Self.denominators.contains(denominator) else { return }

        song.timeSignatureNumerator = numerator
        song.timeSignatureDenominator = denominator

        if let measureOneID = normalizedTimeSignatureChanges.first(where: { $0.startMeasure == 1 })?.id {
            timeSignatureChanges = timeSignatureChanges.map { change in
                guard change.id == measureOneID else { return change }
                return TimeSignatureChange(
                    id: change.id,
                    numerator: numerator,
                    denominator: denominator,
                    startMeasure: 1,
                    sortOrder: change.sortOrder
                )
            }
        } else {
            timeSignatureChanges = [
                TimeSignatureChange(
                    numerator: numerator,
                    denominator: denominator,
                    startMeasure: 1,
                    sortOrder: 0
                )
            ]
        }

        try? modelContext.save()
        onPersist()

        self.numerator = numerator
        self.denominator = denominator
    }
}

struct TempoEditorMenu: View {
    let currentBPM: Double
    let onApply: (Double) -> Void

    @State private var bpm: Double
    @State private var bpmText: String
    @FocusState private var isBPMFieldFocused: Bool

    init(currentBPM: Double, onApply: @escaping (Double) -> Void) {
        self.currentBPM = currentBPM
        self.onApply = onApply
        _bpm = State(initialValue: currentBPM)
        _bpmText = State(initialValue: Self.formatBPM(currentBPM))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo")
                .font(.headline)

            Text("Edits the measure 1 tempo marker.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 88)
                    .focused($isBPMFieldFocused)
                    .onSubmit(commitTextField)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                Text("BPM")
                    .foregroundStyle(.secondary)

                Stepper(
                    "",
                    value: Binding(
                        get: { bpm },
                        set: { applyTempo($0) }
                    ),
                    in: TempoChange.validBPMRange,
                    step: 0.1
                )
                .labelsHidden()
            }
        }
        .padding()
        .frame(minWidth: 280)
        .onChange(of: currentBPM) { _, newValue in
            guard abs(newValue - bpm) >= 0.0001 else { return }
            bpm = newValue
            bpmText = Self.formatBPM(newValue)
        }
        .onChange(of: isBPMFieldFocused) { _, focused in
            if !focused {
                commitTextField()
            }
        }
    }

    private func commitTextField() {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized) else {
            bpmText = Self.formatBPM(bpm)
            return
        }
        applyTempo(value)
    }

    private func applyTempo(_ value: Double) {
        let clamped = min(
            max(value, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
        bpm = clamped
        bpmText = Self.formatBPM(clamped)
        onApply(clamped)
    }

    private static func formatBPM(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

struct TempoMarkerEditorMenu: View {
    let marker: TempoChange
    let canDelete: Bool
    let onApply: (Double) -> Void
    let onDelete: () -> Void

    @State private var bpm: Double
    @State private var bpmText: String

    init(
        marker: TempoChange,
        canDelete: Bool,
        onApply: @escaping (Double) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.marker = marker
        self.canDelete = canDelete
        self.onApply = onApply
        self.onDelete = onDelete
        _bpm = State(initialValue: marker.bpm)
        _bpmText = State(initialValue: String(format: "%.1f", marker.bpm))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo at Measure \(marker.startMeasure)")
                .font(.headline)

            Text("Affects measure grid spacing and playback speed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField("BPM", text: $bpmText)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 88)
                    .onSubmit(commitTextField)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif

                Text("BPM")
                    .foregroundStyle(.secondary)

                Stepper(
                    "",
                    value: Binding(
                        get: { bpm },
                        set: { updateBPM($0) }
                    ),
                    in: TempoChange.validBPMRange,
                    step: 0.1
                )
                .labelsHidden()

                Button("Apply") {
                    commitTextField()
                    onApply(bpm)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
            }

            if canDelete {
                Divider()

                Button("Delete Marker", role: .destructive) {
                    onDelete()
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func commitTextField() {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized) else {
            bpmText = String(format: "%.1f", bpm)
            return
        }
        updateBPM(value)
    }

    private func updateBPM(_ value: Double) {
        let clamped = min(
            max(value, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
        bpm = clamped
        bpmText = String(format: "%.1f", clamped)
    }
}

struct TimeSignatureMarkerEditorMenu: View {
    let marker: TimeSignatureChange
    let canDelete: Bool
    let onApply: (Int, Int) -> Void
    let onDelete: () -> Void

    @State private var numerator: Int
    @State private var denominator: Int

    private static let presets: [(numerator: Int, denominator: Int)] = [
        (4, 4), (3, 4), (2, 4), (6, 8), (5, 4), (7, 8), (12, 8)
    ]

    private static let denominators = [2, 4, 8, 16]

    init(
        marker: TimeSignatureChange,
        canDelete: Bool,
        onApply: @escaping (Int, Int) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.marker = marker
        self.canDelete = canDelete
        self.onApply = onApply
        self.onDelete = onDelete
        _numerator = State(initialValue: marker.numerator)
        _denominator = State(initialValue: marker.denominator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Measure \(marker.startMeasure)")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(Array(Self.presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        numerator = preset.numerator
                        denominator = preset.denominator
                    } label: {
                        Text("\(preset.numerator)/\(preset.denominator)")
                            .font(.body.monospacedDigit().weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .appEditorToolbarPill()
                    .tint(
                        numerator == preset.numerator && denominator == preset.denominator
                            ? AppColors.accent
                            : .secondary
                    )
                }
            }

            Divider()

            HStack(spacing: 16) {
                Stepper(value: $numerator, in: 1...32) {
                    Text("Beats: \(numerator)")
                        .monospacedDigit()
                }

                Picker("Beat value", selection: $denominator) {
                    ForEach(Self.denominators, id: \.self) { value in
                        Text("1/\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            Button("Apply") {
                onApply(numerator, denominator)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)

            if canDelete {
                Divider()

                Button("Delete Marker", role: .destructive) {
                    onDelete()
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}
