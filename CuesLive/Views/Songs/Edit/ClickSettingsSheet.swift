import SwiftData
import SwiftUI

/// The song's click: whether it plays, how often, and which sound. Changes are heard right
/// away and become one undo step when the sheet closes.
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
                    Picker("Sound", selection: $settings.sound) {
                        ForEach(ClickSound.allCases) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Auto clicks on each beat of the time signature: quarters in 4/4, eighths in 6/8.")
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
            editStartSnapshot = captureSnapshot()
        }
        .onChange(of: settings) { _, newSettings in
            apply(newSettings)
        }
        .onDisappear(perform: commitUndoIfNeeded)
    }

    private func apply(_ newSettings: ClickSettings) {
        guard newSettings != song.clickSettings else { return }
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
