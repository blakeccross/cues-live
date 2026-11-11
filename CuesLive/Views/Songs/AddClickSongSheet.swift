import SwiftData
import SwiftUI

struct AddClickSongSheet: View {
    var onCreate: (String, Double, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @FocusState private var songNameFocused: Bool

    @State private var songName = ""
    @State private var bpmText = "120"
    @State private var selectedPreset = MeterPreset(
        numerator: TimeSignatureChange.defaultNumerator,
        denominator: TimeSignatureChange.defaultDenominator
    )

    private struct MeterPreset: Hashable {
        let numerator: Int
        let denominator: Int

        var label: String { "\(numerator)/\(denominator)" }
    }

    private static let presets: [MeterPreset] = [
        MeterPreset(numerator: 4, denominator: 4),
        MeterPreset(numerator: 3, denominator: 4),
        MeterPreset(numerator: 2, denominator: 4),
        MeterPreset(numerator: 6, denominator: 8),
        MeterPreset(numerator: 5, denominator: 4),
        MeterPreset(numerator: 7, denominator: 8),
        MeterPreset(numerator: 12, denominator: 8)
    ]

    private var canCreate: Bool {
        !songName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedBPM != nil
    }

    private var parsedBPM: Double? {
        let sanitized = bpmText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(sanitized), value > 0, value.isFinite else {
            return nil
        }
        return min(
            max(value, TempoChange.validBPMRange.lowerBound),
            TempoChange.validBPMRange.upperBound
        )
    }

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Song name")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)

                        TextField("My Song", text: $songName)
                            .textFieldStyle(.roundedBorder)
                            .focused($songNameFocused)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Tempo (BPM)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)

                        TextField("120", text: $bpmText)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Meter")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)

                        Picker("Meter", selection: $selectedPreset) {
                            ForEach(Self.presets, id: \.self) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }

                    Text("Creates an 8-bar click track set to loop.")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(AppSpacing.lg)
                .frame(minWidth: 360, minHeight: 280)
                .navigationTitle("Add Click")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createClickSong()
                        }
                        .foregroundStyle(canCreate ? AppColors.accent : AppColors.textTertiary)
                        .disabled(!canCreate)
                    }
                }
                .onAppear {
                    songNameFocused = true
                }
            }
        }
    }

    private func createClickSong() {
        guard let bpm = parsedBPM else { return }
        onCreate(
            songName.trimmingCharacters(in: .whitespacesAndNewlines),
            bpm,
            selectedPreset.numerator,
            selectedPreset.denominator
        )
    }
}
