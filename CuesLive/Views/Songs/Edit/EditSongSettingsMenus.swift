import SwiftUI

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

/// Tempo Operations window: a constant, a ramp, a stretch, or a scale
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
