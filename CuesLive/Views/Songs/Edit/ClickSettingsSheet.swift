import SwiftData
import SwiftUI

/// The song's click: whether it plays, how often, and which sound. One menu picks a sound's
/// accent and normal pair; a collapsed group gives the accent and the beats any sample and their
/// own volume. Changes are heard right away and become one undo step when the sheet closes.
struct ClickSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let song: Song
    let viewModel: SongEditorViewModel
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void

    @State private var settings = ClickSettings()
    @State private var editStartSnapshot: SongEditSnapshot?
    @State private var saveError: String?
    @State private var showsAccentAndBeat = false
    /// True while a volume slider is being dragged: the click follows it, and saves on release.
    @State private var isAdjustingVolume = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Play Click", isOn: $settings.isEnabled)
                } footer: {
                    Text("Plays from the song's tempo map through the Click output. It isn't added as a track.")
                }

                Section {
                    Picker("Rhythm", selection: $settings.rhythm) {
                        ForEach(ClickRhythm.allCases) { rhythm in
                            Text(rhythm.displayName).tag(rhythm)
                        }
                    }
                    soundPicker
                    DisclosureGroup(isExpanded: $showsAccentAndBeat) {
                        accentAndBeatControls
                    } label: {
                        accentAndBeatToggle
                    }
                } footer: {
                    Text("Auto clicks on each beat of the time signature: quarters in 4/4, eighths in 6/8. The accent is the first click of each bar.")
                }
                .disabled(!settings.isEnabled)

                if let saveError {
                    Text(saveError)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.error)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Click")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .standardDialogToolbar()
        .frame(minWidth: 360, minHeight: 300)
        .onAppear {
            settings = song.clickSettings
            showsAccentAndBeat = settings.isCustomized
            editStartSnapshot = captureSnapshot()
        }
        .onChange(of: settings) { _, newSettings in
            if isAdjustingVolume {
                viewModel.previewClickSettings(newSettings)
            } else {
                apply(newSettings)
            }
        }
        .onDisappear(perform: commitUndoIfNeeded)
    }

    /// Sets a sound's accent and normal pair. Shows Custom for any other combination.
    private var soundPicker: some View {
        Picker("Sound", selection: $settings.sound) {
            ForEach(ClickSound.allCases) { sound in
                Text(sound.displayName).tag(Optional(sound))
            }
            if settings.sound == nil {
                Text("Custom").tag(ClickSound?.none)
            }
        }
        .pickerStyle(.menu)
    }

    /// The whole row expands the group, not just its disclosure triangle, which is a small
    /// target on the Mac.
    private var accentAndBeatToggle: some View {
        Button {
            withAnimation {
                showsAccentAndBeat.toggle()
            }
        } label: {
            Text("Customize Accent and Beat")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var accentAndBeatControls: some View {
        samplePicker("Accent Sound", selection: $settings.accentSample)
        volumeSlider("Accent Volume", value: $settings.accentVolume)
        samplePicker("Beat Sound", selection: $settings.beatSample)
        volumeSlider("Beat Volume", value: $settings.beatVolume)
    }

    /// Any sound's accent or normal sample, so the beats can use an accent sample and vice versa.
    private func samplePicker(_ title: String, selection: Binding<ClickSample>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ClickSample.allCases) { sample in
                Text(sample.displayName).tag(sample)
            }
        }
        .pickerStyle(.menu)
    }

    private func volumeSlider(_ title: String, value: Binding<Double>) -> some View {
        Slider(value: value, in: 0...ClickSettings.fullVolume) {
            Text(title)
        } minimumValueLabel: {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
        } maximumValueLabel: {
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        } onEditingChanged: { isEditing in
            isAdjustingVolume = isEditing
            if !isEditing {
                save(settings)
            }
        }
    }

    private func apply(_ newSettings: ClickSettings) {
        guard newSettings != song.clickSettings else { return }
        save(newSettings)
    }

    private func save(_ newSettings: ClickSettings) {
        do {
            try viewModel.updateClickSettings(newSettings, context: modelContext)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func commitUndoIfNeeded() {
        guard let before = editStartSnapshot else { return }
        let after = captureSnapshot()
        if before != after {
            registerUndo("Change Click", before, after)
        }
        editStartSnapshot = nil
    }
}
