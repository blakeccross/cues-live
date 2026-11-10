import SwiftUI

/// macOS live-mapping side panel listing current bindings for edit or remove.
struct InputMappingPanel: View {
    @Environment(InputMappingController.self) private var mapping
    @Bindable private var store = InputMappingStore.shared

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            mappingList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.backgroundSecondary)
    }

    private var headerBar: some View {
        ZStack {
            Text(mapping.sessionTitle)
                .appLargeTitle()

            HStack {
                Spacer()
                Button {
                    mapping.endMapping()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .appLinkPointer()
                .accessibilityLabel("Done mapping")
                .help("Done")
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
    }

    private var mappingList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                transportSection
                songsSection
                sectionsSection
                helpText
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.bottom, AppSpacing.lg)
        }
        .scrollContentBackground(.hidden)
    }

    private var transportSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSectionHeader(title: "Transport")

            VStack(spacing: 0) {
                ForEach(Array(MappableLiveAction.transportActions.enumerated()), id: \.element.id) { index, action in
                    mappingRow(for: action)
                    if index < MappableLiveAction.transportActions.count - 1 {
                        Divider()
                            .background(AppColors.separator)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var songsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSectionHeader(title: "Songs")

            let songs = mappedSongActions
            VStack(alignment: .leading, spacing: 0) {
                if songs.isEmpty {
                    Text(emptySongsMessage)
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpacing.sm)
                } else {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, action in
                        mappingRow(for: action)
                        if index < songs.count - 1 {
                            Divider()
                                .background(AppColors.separator)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var helpText: some View {
        Text(helpMessage)
            .font(.caption)
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.xs)
    }

    private var sectionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSectionHeader(title: "Sections")

            let sections = mappedSectionActions
            VStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    Text(emptySectionsMessage)
                        .font(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpacing.sm)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, action in
                        mappingRow(for: action)
                        if index < sections.count - 1 {
                            Divider()
                                .background(AppColors.separator)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var mappedSongActions: [MappableLiveAction] {
        store.songMappings
            .compactMap { record -> MappableLiveAction? in
                guard sessionBindingLabel(for: record) != nil else { return nil }
                return record.action
            }
    }

    private var mappedSectionActions: [MappableLiveAction] {
        store.sectionMappings
            .compactMap { record -> MappableLiveAction? in
                guard sessionBindingLabel(for: record) != nil else { return nil }
                return record.action
            }
    }

    private var emptySongsMessage: String {
        switch mapping.session {
        case .keyMapping:
            "No song keys mapped yet. Tap a song in the setlist, then press a key."
        case .midiMapping:
            "No song MIDI notes mapped yet. Tap a song in the setlist, then send a MIDI note."
        case .idle:
            "No song mappings yet."
        }
    }

    private var emptySectionsMessage: String {
        switch mapping.session {
        case .keyMapping:
            "No section keys mapped yet. Tap a section on a song waveform, then press a key."
        case .midiMapping:
            "No section MIDI notes mapped yet. Tap a section on a song waveform, then send a MIDI note."
        case .idle:
            "No section mappings yet."
        }
    }

    private var helpMessage: String {
        "Tap a binding to reassign it, or remove to clear. Escape cancels."
    }

    private func mappingRow(for action: MappableLiveAction) -> some View {
        let record = store.mapping(for: action)
        let bindingLabel = sessionBindingLabel(for: record)
        let isLearning = mapping.pendingAction == action
        let hasBinding = bindingLabel != nil

        return HStack(alignment: .center, spacing: AppSpacing.sm) {
            Image(systemName: action.systemImage)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22)

            Text(action.title)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Button {
                mapping.selectAction(action)
            } label: {
                Text(isLearning ? learningPlaceholder : (bindingLabel ?? unmappedPlaceholder))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .foregroundStyle(isLearning || hasBinding ? AppColors.textPrimary : AppColors.textSecondary)
                    .background(
                        isLearning ? AppColors.accent : AppColors.backgroundSecondary,
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isLearning ? AppColors.accent : AppColors.separator,
                                lineWidth: isLearning ? 1.5 : 0.5
                            )
                    }
            }
            .buttonStyle(.plain)
            .help(isLearning ? learningPlaceholder : (hasBinding ? "Click to reassign" : "Click to assign"))

            if hasBinding {
                Button {
                    clearSessionBinding(for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(removeHelp)
                .accessibilityLabel(removeAccessibilityLabel(for: action))
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .contextMenu {
            if hasBinding {
                Button(removeMenuTitle, role: .destructive) {
                    clearSessionBinding(for: action)
                }
            }
        }
    }

    private var learningPlaceholder: String {
        switch mapping.session {
        case .keyMapping: "Press key…"
        case .midiMapping: "Send MIDI…"
        case .idle: "…"
        }
    }

    private var unmappedPlaceholder: String {
        switch mapping.session {
        case .keyMapping: "Key"
        case .midiMapping: "MIDI"
        case .idle: "—"
        }
    }

    private var removeHelp: String {
        switch mapping.session {
        case .keyMapping: "Remove key"
        case .midiMapping: "Remove MIDI"
        case .idle: "Remove"
        }
    }

    private var removeMenuTitle: String {
        switch mapping.session {
        case .keyMapping: "Clear Key"
        case .midiMapping: "Clear MIDI"
        case .idle: "Clear"
        }
    }

    private func removeAccessibilityLabel(for action: MappableLiveAction) -> String {
        "\(removeHelp) for \(action.title)"
    }

    private func sessionBindingLabel(for record: InputMapping?) -> String? {
        guard let record else { return nil }
        switch mapping.session {
        case .keyMapping:
            return record.key?.displayName
        case .midiMapping:
            return record.midi?.displayName
        case .idle:
            return nil
        }
    }

    private func clearSessionBinding(for action: MappableLiveAction) {
        switch mapping.session {
        case .keyMapping:
            store.clearKey(for: action)
        case .midiMapping:
            store.clearMIDI(for: action)
        case .idle:
            break
        }
        if mapping.pendingAction == action {
            mapping.selectAction(action)
        }
    }
}
