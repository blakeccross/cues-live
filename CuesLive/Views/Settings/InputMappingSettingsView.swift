import SwiftUI

struct InputMappingSettingsView: View {
    @Environment(InputMappingController.self) private var mapping
    @Bindable private var store = InputMappingStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(MappableLiveAction.transportActions) { action in
                    mappingRow(for: action)
                }
            } header: {
                Text("Transport")
            }

            Section {
                let songs = store.songMappings
                if songs.isEmpty {
                    Text("No song mappings yet. Use Key Mapping or MIDI Mapping on the live setlist, then tap a song.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(songs) { item in
                        mappingRow(for: item.action)
                    }
                }
            } header: {
                Text("Songs")
            } footer: {
                Text("Mapped keys and MIDI notes trigger the same actions as tapping Stop, Play, Fade, Loop, or a setlist song. Escape cancels mapping.")
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            if mapping.endsSessionAfterAssign {
                mapping.endMapping()
            }
        }
    }

    private func mappingRow(for action: MappableLiveAction) -> some View {
        let record = store.mapping(for: action)
        let isLearningKey = mapping.session == .keyMapping && mapping.pendingAction == action
        let isLearningMIDI = mapping.session == .midiMapping && mapping.pendingAction == action

        return LabeledContent {
            HStack(spacing: 8) {
                bindingButton(
                    title: isLearningKey ? "Press key…" : (record?.key?.displayName ?? "Key"),
                    isLearning: isLearningKey
                ) {
                    mapping.startSettingsLearn(action: action, session: .keyMapping)
                }
                .contextMenu {
                    if record?.key != nil {
                        Button("Clear Key", role: .destructive) {
                            store.clearKey(for: action)
                        }
                    }
                }

                bindingButton(
                    title: isLearningMIDI ? "Send MIDI…" : (record?.midi?.displayName ?? "MIDI"),
                    isLearning: isLearningMIDI
                ) {
                    mapping.startSettingsLearn(action: action, session: .midiMapping)
                }
                .contextMenu {
                    if record?.midi != nil {
                        Button("Clear MIDI", role: .destructive) {
                            store.clearMIDI(for: action)
                        }
                    }
                }
            }
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
    }

    private func bindingButton(
        title: String,
        isLearning: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(isLearning ? Color.accentColor : nil)
            .fixedSize()
            .help(isLearning ? title : "Click to assign")
    }
}
