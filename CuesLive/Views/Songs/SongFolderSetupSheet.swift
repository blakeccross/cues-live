import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SongFolderSetupSession: Identifiable {
    let id = UUID()
    let previews: [SongFolderImporter.Preview]
    /// The setlist row the imported songs are inserted at, or nil to import into the library only.
    var setlistRowIndex: Int?
}

struct SongFolderSetupSheet: View {
    let previews: [SongFolderImporter.Preview]
    let onFinish: ([SongFolderImporter.ImportRequest]) -> Void

    @FocusState private var songNameFocused: Bool

    @State private var index: Int
    @State private var songName: String
    @State private var bpmText: String
    @State private var selectedPreset: MeterPreset
    @State var keySelection: String
    @State var keyMode: SongKeyMode = .major
    @State var keyDetection: KeyDetectionState = .idle
    @State var keyDetectionTask: Task<Void, Never>?
    @State private var confirmed: [SongFolderImporter.ImportRequest] = []
    @State private var didFinish = false

    private struct MeterPreset: Hashable {
        let numerator: Int
        let denominator: Int

        var label: String { "\(numerator)/\(denominator)" }
    }

    private static let standardPresets: [MeterPreset] = [
        MeterPreset(numerator: 4, denominator: 4),
        MeterPreset(numerator: 3, denominator: 4),
        MeterPreset(numerator: 2, denominator: 4),
        MeterPreset(numerator: 6, denominator: 8),
        MeterPreset(numerator: 5, denominator: 4),
        MeterPreset(numerator: 7, denominator: 8),
        MeterPreset(numerator: 12, denominator: 8)
    ]

    init(previews: [SongFolderImporter.Preview], onFinish: @escaping ([SongFolderImporter.ImportRequest]) -> Void) {
        self.previews = previews
        self.onFinish = onFinish
        let first = previews[0]
        _index = State(initialValue: 0)
        _songName = State(initialValue: first.suggestedName)
        _bpmText = State(initialValue: Self.formatBPM(first.bpm ?? TempoChange.defaultBPM))
        _selectedPreset = State(initialValue: Self.preset(for: first))
        _keySelection = State(initialValue: "")
    }

    private static let tempoFieldWidth: CGFloat = 72

    var currentPreview: SongFolderImporter.Preview {
        previews[index]
    }

    private var isLastSong: Bool {
        index >= previews.count - 1
    }

    private var meterPresets: [MeterPreset] {
        var presets = Self.standardPresets
        let detected = Self.preset(for: currentPreview)
        if !presets.contains(detected) {
            presets.insert(detected, at: 0)
        }
        if !presets.contains(selectedPreset) {
            presets.insert(selectedPreset, at: 0)
        }
        return presets
    }

    private var canContinue: Bool {
        !songName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedBPM != nil
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
        NavigationStack {
            Form {
                songSection
                timingSection
                keySection
            }
            .formStyle(.grouped)
            .navigationTitle("Import Song")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        finish(includingCurrent: false)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLastSong ? "Add" : "Next") {
                        continueImport()
                    }
                    .disabled(!canContinue)
                }
            }
            .onAppear {
                songNameFocused = true
            }
        }
        .standardDialogToolbar()
        .formSheetFrame(minWidth: 420, minHeight: 440)
        .interactiveDismissDisabled(true)
        .onDisappear(perform: cancelKeyDetection)
    }

    private var songSection: some View {
        Section {
            TextField("Name", text: $songName, prompt: Text("Song name"))
                .focused($songNameFocused)
            LabeledContent("Folder", value: currentPreview.folderURL.lastPathComponent)
        } header: {
            if previews.count > 1 {
                Text("Song \(index + 1) of \(previews.count)")
            }
        }
    }

    private var timingSection: some View {
        Section {
            LabeledContent("Tempo") {
                HStack(spacing: AppSpacing.xs) {
                    TextField("Tempo", text: $bpmText, prompt: Text("120"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: Self.tempoFieldWidth)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text("BPM")
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Time Signature", selection: $selectedPreset) {
                ForEach(meterPresets, id: \.self) { preset in
                    Text(preset.label).tag(preset)
                }
            }
        } footer: {
            if currentPreview.bpm != nil || currentPreview.timeSignatureNumerator != nil {
                Text("Tempo and time signature were read from the Ableton set.")
            }
        }
    }

    private func continueImport() {
        guard let request = currentRequest() else { return }
        if isLastSong {
            finish(includingCurrent: true)
        } else {
            confirmed.append(request)
            index += 1
            loadPreview(currentPreview)
            songNameFocused = true
        }
    }

    private func currentRequest() -> SongFolderImporter.ImportRequest? {
        guard let bpm = parsedBPM else { return nil }
        let name = songName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return SongFolderImporter.ImportRequest(
            folderURL: currentPreview.folderURL,
            settings: SongFolderImporter.ImportSettings(
                name: name,
                bpm: bpm,
                timeSignatureNumerator: selectedPreset.numerator,
                timeSignatureDenominator: selectedPreset.denominator,
                baseKeyRaw: keySelection.isEmpty ? nil : keySelection,
                keyModeRaw: keySelection.isEmpty ? nil : keyMode.storedRaw
            )
        )
    }

    private func finish(includingCurrent: Bool) {
        guard !didFinish else { return }
        didFinish = true
        cancelKeyDetection()
        var requests = confirmed
        if includingCurrent, let request = currentRequest() {
            requests.append(request)
        }
        onFinish(requests)
    }

    private func loadPreview(_ preview: SongFolderImporter.Preview) {
        songName = preview.suggestedName
        bpmText = Self.formatBPM(preview.bpm ?? TempoChange.defaultBPM)
        selectedPreset = Self.preset(for: preview)
        keySelection = ""
        keyMode = .major
        cancelKeyDetection()
    }

    private static func preset(for preview: SongFolderImporter.Preview) -> MeterPreset {
        let numerator = preview.timeSignatureNumerator ?? TimeSignatureChange.defaultNumerator
        let denominator = preview.timeSignatureDenominator ?? TimeSignatureChange.defaultDenominator
        guard (1...32).contains(numerator), TimeSignatureChange.validDenominators.contains(denominator) else {
            return MeterPreset(
                numerator: TimeSignatureChange.defaultNumerator,
                denominator: TimeSignatureChange.defaultDenominator
            )
        }
        return MeterPreset(numerator: numerator, denominator: denominator)
    }

    private static func formatBPM(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.1f", value)
    }
}
