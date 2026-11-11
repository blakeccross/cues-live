import SwiftUI

/// Clip-gain mark: a short fader, then the decibel readout.
/// Shown on a clip that already has gain. Gain is changed from the menu or a shortcut.
struct ClipGainIcon: View {
    let decibels: Double

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                Rectangle()
                    .frame(width: 1, height: 13)
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 9, height: 3)
                    .offset(y: 2)
            }
            .frame(width: 9, height: 13)
            Text("\(ClipGain.readout(decibels)) dB")
                .font(.system(size: 9.5))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(200.0 / 255.0))
        .fixedSize()
        .contentShape(Rectangle())
        .accessibilityLabel("Clip gain \(ClipGain.readout(decibels)) decibels")
    }
}

/// Asks for a clip gain in decibels. The same value is applied to every selected clip.
struct ClipGainPrompt: View {
    let initialDecibels: Double?
    let clipCount: Int
    let onCancel: () -> Void
    let onApply: (Double) -> Void

    @State private var gainText: String
    @FocusState private var isFieldFocused: Bool

    init(
        initialDecibels: Double?,
        clipCount: Int,
        onCancel: @escaping () -> Void,
        onApply: @escaping (Double) -> Void
    ) {
        self.initialDecibels = initialDecibels
        self.clipCount = clipCount
        self.onCancel = onCancel
        self.onApply = onApply
        if let initialDecibels {
            _gainText = State(initialValue: ClipGain.readout(initialDecibels))
        } else {
            _gainText = State(initialValue: "")
        }
    }

    private var prompt: String {
        if clipCount > 1 {
            return "Set the gain for \(clipCount) selected clips, in decibels. 0 is unity."
        }
        return "Set this clip’s gain in decibels. 0 is unity."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(prompt)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    TextField("0.0", text: $gainText)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 88)
                        .focused($isFieldFocused)
                        .onSubmit(submit)
#if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
#endif

                    Text("dB")
                        .foregroundStyle(.secondary)
                }

                Text("From −144 to +36.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 320, alignment: .leading)
            .navigationTitle("Adjust Gain")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adjust", action: submit)
                        .disabled(parsedDecibels == nil)
                }
            }
        }
        .standardDialogToolbar()
        .onAppear { isFieldFocused = true }
    }

    private var parsedDecibels: Double? {
        let sanitized = gainText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "db", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(sanitized), value.isFinite else { return nil }
        return value
    }

    private func submit() {
        guard let value = parsedDecibels else { return }
        onApply(ClipGain.stored(value))
    }
}
