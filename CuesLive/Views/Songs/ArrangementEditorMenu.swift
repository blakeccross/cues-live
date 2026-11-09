import SwiftUI

/// Section-level edits. Each one moves, copies, or removes the audio on every track along with
/// the section's marker.
struct ArrangementSectionActions {
    let sections: [SongSection]
    let move: (_ sectionID: UUID, _ toIndex: Int) -> Void
    let duplicate: (_ sectionID: UUID) -> Void
    let remove: (_ sectionID: UUID) -> Void
}

struct ArrangementEditorMenu: View {
    let actions: ArrangementSectionActions

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSectionHeader(title: "Song Arrangement")

            Text("Drag to reorder. Reordering, duplicating, or removing a section edits the audio on every track.")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)

            if actions.sections.isEmpty {
                AppEmptyState(
                    title: "No Sections",
                    systemImage: "music.note.list",
                    description: "Add a section marker on the ruler or import an Ableton file."
                )
                .frame(minWidth: 300, minHeight: 180)
            } else {
                List {
                    ForEach(actions.sections) { section in
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "line.3.horizontal")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("\(formatTime(section.timelineStartSeconds)) – \(formatTime(section.timelineEndSeconds))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(AppColors.textSecondary)
                            }

                            Spacer()

                            Button {
                                actions.duplicate(section.id)
                            } label: {
                                Image(systemName: "plus.square.on.square")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Duplicate section")

                            Button(role: .destructive) {
                                actions.remove(section.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove section")
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minWidth: 320, minHeight: 220, maxHeight: 420)
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surfaceElevated, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let index = source.first, index < actions.sections.count else { return }
        actions.move(actions.sections[index].id, destination)
    }
}
