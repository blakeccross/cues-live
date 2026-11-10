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

/// Asks which tempo a double-click on the tempo lane should use.
struct TempoChangePrompt: View {
    let measure: Int
    let currentBPM: Double
    let onCancel: () -> Void
    let onChange: (Double) -> Void

    @State private var bpmText: String
    @FocusState private var isFieldFocused: Bool

    init(
        measure: Int,
        currentBPM: Double,
        onCancel: @escaping () -> Void,
        onChange: @escaping (Double) -> Void
    ) {
        self.measure = measure
        self.currentBPM = currentBPM
        self.onCancel = onCancel
        self.onChange = onChange
        _bpmText = State(initialValue: String(format: "%.1f", currentBPM))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("What tempo should measure \(measure) change to?")
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
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
            }
            .padding()
            .frame(minWidth: 320, alignment: .leading)
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
        .onAppear { isFieldFocused = true }
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
        onChange(clamped)
    }
}

/// Asks which time signature a double-click on the time signature lane should use.
struct TimeSignatureChangePrompt: View {
    let measure: Int
    let numerator: Int
    let denominator: Int
    let onCancel: () -> Void
    let onChange: (Int, Int) -> Void

    @State private var signatureText: String
    @FocusState private var isFieldFocused: Bool

    init(
        measure: Int,
        numerator: Int,
        denominator: Int,
        onCancel: @escaping () -> Void,
        onChange: @escaping (Int, Int) -> Void
    ) {
        self.measure = measure
        self.numerator = numerator
        self.denominator = denominator
        self.onCancel = onCancel
        self.onChange = onChange
        _signatureText = State(initialValue: "\(numerator)/\(denominator)")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("What time signature should measure \(measure) change to?")
                    .fixedSize(horizontal: false, vertical: true)

                TextField("4/4", text: $signatureText)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($isFieldFocused)
                    .onSubmit(submit)
#if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
#endif
            }
            .padding()
            .frame(minWidth: 320, alignment: .leading)
            .navigationTitle("Change Time Signature")
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
        .onAppear { isFieldFocused = true }
    }

    private func submit() {
        let parts = signatureText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2,
              let numerator = Int(parts[0]),
              let denominator = Int(parts[1]),
              (1...32).contains(numerator),
              TimeSignatureChange.validDenominators.contains(denominator) else { return }
        onChange(numerator, denominator)
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
            Text("Tempo at \(marker.positionLabel)")
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

/// SoundCraft's Tempo Operations window: a constant, a ramp, a stretch, or a scale
/// over a bar range. The tempo in effect at the end bar is left in place.
struct TempoOperationsMenu: View {
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let playhead: TimeInterval
    let onApply: ([TempoChange]) -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case constant, linear, parabolic, sCurve, stretch, scale

        var id: String { rawValue }

        var title: String {
            switch self {
            case .constant: "Constant"
            case .linear: "Linear"
            case .parabolic: "Parabolic"
            case .sCurve: "S-Curve"
            case .stretch: "Stretch"
            case .scale: "Scale"
            }
        }

        var usesRange: Bool { self != .scale }
        var usesCurve: Bool { self == .linear || self == .parabolic || self == .sCurve }
        var usesFactor: Bool { self == .stretch || self == .scale }
    }

    @State private var kind: Kind
    @State private var startBar: Int
    @State private var endBar: Int
    @State private var startBPM: Double
    @State private var endBPM: Double
    @State private var resolution: TempoResolution = .eighth
    @State private var curvature: Double = 0.5
    @State private var factor: Double = 2
    @State private var errorMessage: String?

    init(
        tempoChanges: [TempoChange],
        timeSignatureChanges: [TimeSignatureChange],
        playhead: TimeInterval,
        onApply: @escaping ([TempoChange]) -> Void
    ) {
        self.tempoChanges = tempoChanges
        self.timeSignatureChanges = timeSignatureChanges
        self.playhead = playhead
        self.onApply = onApply
        let bar = max(
            1,
            MeasureTiming.measureIndex(
                at: playhead,
                tempoChanges: tempoChanges,
                timeSignatureChanges: timeSignatureChanges
            )
        )
        let bpm = MeasureTiming.bpmForMeasure(bar, tempoChanges: tempoChanges)
        _kind = State(initialValue: .linear)
        _startBar = State(initialValue: bar)
        _endBar = State(initialValue: bar + 4)
        _startBPM = State(initialValue: bpm)
        _endBPM = State(initialValue: bpm)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tempo Operations")
                .font(.headline)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Operation", selection: $kind) {
                ForEach(Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            if kind.usesRange {
                HStack(spacing: 16) {
                    Stepper(value: $startBar, in: 1...9_999) {
                        Text("Start bar \(startBar)")
                            .monospacedDigit()
                    }
                    Stepper(value: $endBar, in: 2...10_000) {
                        Text("End bar \(endBar)")
                            .monospacedDigit()
                    }
                }
            }

            if kind == .constant {
                bpmField("BPM", value: $startBPM)
            }

            if kind.usesCurve {
                HStack(spacing: 16) {
                    bpmField("Start", value: $startBPM)
                    bpmField("End", value: $endBPM)
                }
                Picker("Resolution", selection: $resolution) {
                    ForEach(TempoResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
                if kind == .parabolic {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Curvature \(curvature, format: .number.precision(.fractionLength(2)))")
                            .font(.caption)
                            .monospacedDigit()
                        Slider(value: $curvature, in: -1...1)
                    }
                }
            }

            if kind.usesFactor {
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind == .stretch ? "Length factor \(factor, format: .number.precision(.fractionLength(2)))" : "Tempo factor \(factor, format: .number.precision(.fractionLength(2)))")
                        .font(.caption)
                        .monospacedDigit()
                    Slider(value: $factor, in: 0.05...20)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Apply") {
                apply()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .padding()
        .frame(minWidth: 360)
    }

    private var caption: String {
        switch kind {
        case .constant:
            "Holds one tempo from the start bar up to the end bar. The tempo at the end bar stays as it was."
        case .linear, .parabolic, .sCurve:
            "Samples the ramp onto the tempo map. The tempo at the end bar stays as it was."
        case .stretch:
            "Scales the tempos in the range so those bars last this many times as long."
        case .scale:
            "Multiplies every tempo in the song."
        }
    }

    private func bpmField(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            TextField(
                "BPM",
                value: value,
                format: .number.precision(.fractionLength(1))
            )
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 72)
            Stepper("", value: value, in: TempoChange.validBPMRange, step: 0.1)
                .labelsHidden()
        }
    }

    private func apply() {
        let signatures = timeSignatureChanges
        let start = TempoTimeline.tick(measure: startBar, beatOffset: 0, timeSignatureChanges: signatures)
        let end = TempoTimeline.tick(measure: max(endBar, startBar + 1), beatOffset: 0, timeSignatureChanges: signatures)
        let result: Result<[TempoChange], TempoOperationError>
        switch kind {
        case .constant:
            result = TempoOperations.constant(
                bpm: startBPM,
                from: start,
                to: end,
                tempoChanges: tempoChanges,
                timeSignatureChanges: signatures
            )
        case .linear, .parabolic, .sCurve:
            let curve: TempoCurve = switch kind {
            case .parabolic: .parabolic
            case .sCurve: .sCurve
            default: .linear
            }
            result = TempoOperations.curve(
                curve,
                startBPM: startBPM,
                endBPM: endBPM,
                from: start,
                to: end,
                resolutionTicks: resolution.ticks,
                curvature: curvature,
                tempoChanges: tempoChanges,
                timeSignatureChanges: signatures
            )
        case .stretch:
            result = TempoOperations.stretch(
                factor: factor,
                from: start,
                to: end,
                tempoChanges: tempoChanges,
                timeSignatureChanges: signatures
            )
        case .scale:
            result = TempoOperations.scale(
                factor: factor,
                tempoChanges: tempoChanges,
                timeSignatureChanges: signatures
            )
        }

        switch result {
        case .success(let changes):
            errorMessage = nil
            onApply(changes)
        case .failure(let error):
            errorMessage = error.message
        }
    }
}
