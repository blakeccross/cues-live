import SwiftUI

/// Live-mapping inspector. A segmented control picks key or MIDI mapping, and a grouped
/// form lists every mappable control with its binding for the chosen mode.
@MainActor
struct InputMappingPanel: View {
    @Environment(InputMappingController.self) private var mapping
    @Bindable private var store = InputMappingStore.shared

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            mappingForm
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundSecondary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = mapping.statusMessage {
                statusBar(message)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppAnimation.springSmooth, value: mapping.statusMessage)
        #if os(iOS)
        // Buttons in the inspector take focus on iPad, so learn keys pressed while they hold it.
        .onKeyPress(phases: .down) { press in
            guard let binding = KeyBinding(keyPress: press) else { return .ignored }
            return mapping.handleKey(binding) ? .handled : .ignored
        }
        #endif
    }

    private var modeBar: some View {
        VStack(spacing: AppSpacing.xs) {
            AppSegmentedPicker(
                title: "Mapping Mode",
                options: [("Keys", .keyMapping), ("MIDI", .midiMapping)],
                selection: modeSelection
            )

            Text(instruction)
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
    }

    private var mappingForm: some View {
        Form {
            Section("Transport") {
                ForEach(MappableLiveAction.transportActions) { action in
                    mappingRow(for: action)
                }
            }

            Section("Songs") {
                let songs = mappedActions(in: store.songMappings)
                if songs.isEmpty {
                    emptyRow(emptySongsMessage)
                } else {
                    ForEach(songs) { action in
                        mappingRow(for: action)
                    }
                }
            }

            Section {
                let sections = mappedActions(in: store.sectionMappings)
                if sections.isEmpty {
                    emptyRow(emptySectionsMessage)
                } else {
                    ForEach(sections) { action in
                        mappingRow(for: action)
                    }
                }
            } header: {
                Text("Sections")
            } footer: {
                Text("Right-click a binding to clear it. Escape cancels a pending assignment.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statusBar(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(.bar)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func mappingRow(for action: MappableLiveAction) -> some View {
        let bindingLabel = sessionBindingLabel(for: store.mapping(for: action))
        let isLearning = mapping.pendingAction == action

        return LabeledContent {
            HStack(spacing: AppSpacing.xs) {
                Button(isLearning ? learningPlaceholder : (bindingLabel ?? "Assign")) {
                    mapping.selectAction(action)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(isLearning ? AppColors.accent : nil)
                .fixedSize()
                .help(isLearning ? learningPlaceholder : (bindingLabel == nil ? "Click to assign" : "Click to reassign"))
                .accessibilityLabel("\(action.title) \(modeNoun)")
                .accessibilityValue(isLearning ? learningPlaceholder : (bindingLabel ?? "Not assigned"))

                if bindingLabel != nil {
                    Button {
                        clearSessionBinding(for: action)
                    } label: {
                        Label(clearTitle, systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.borderless)
                    .help(clearTitle)
                    .accessibilityLabel("\(clearTitle) for \(action.title)")
                }
            }
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .lineLimit(1)
        }
        .contextMenu {
            if bindingLabel != nil {
                Button(clearTitle, role: .destructive) {
                    clearSessionBinding(for: action)
                }
            }
        }
    }

    private var modeSelection: Binding<InputMappingSession> {
        Binding(
            get: { mapping.session == .idle ? mapping.preferredSession : mapping.session },
            set: { mapping.switchSession(to: $0) }
        )
    }

    private var isMIDI: Bool { mapping.session == .midiMapping }

    private var modeNoun: String { isMIDI ? "MIDI note" : "key" }

    private var instruction: String {
        isMIDI
            ? "Choose a control, then send a MIDI note. Tap songs or sections to add them."
            : "Choose a control, then press a key. Tap songs or sections to add them."
    }

    private var learningPlaceholder: String { isMIDI ? "Send MIDI…" : "Press Key…" }

    private var clearTitle: String { isMIDI ? "Clear MIDI" : "Clear Key" }

    private var emptySongsMessage: String {
        "No songs mapped. Tap a song in the setlist, then \(isMIDI ? "send a MIDI note" : "press a key")."
    }

    private var emptySectionsMessage: String {
        "No sections mapped. Tap a section on a song waveform, then \(isMIDI ? "send a MIDI note" : "press a key")."
    }

    private func mappedActions(in records: [InputMapping]) -> [MappableLiveAction] {
        records.compactMap { record in
            sessionBindingLabel(for: record) == nil ? nil : record.action
        }
    }

    private func sessionBindingLabel(for record: InputMapping?) -> String? {
        guard let record else { return nil }
        switch mapping.session {
        case .keyMapping: return record.key?.displayName
        case .midiMapping: return record.midi?.displayName
        case .idle: return nil
        }
    }

    private func clearSessionBinding(for action: MappableLiveAction) {
        switch mapping.session {
        case .keyMapping: store.clearKey(for: action)
        case .midiMapping: store.clearMIDI(for: action)
        case .idle: break
        }
        if mapping.pendingAction == action {
            mapping.selectAction(action)
        }
    }
}
