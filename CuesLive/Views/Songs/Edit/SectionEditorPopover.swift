import SwiftUI

/// Edits a section marker in a popover anchored to its block on the marker ruler. Reads like a
/// menu: the user's section names, then Rename… for a custom name, then a link to manage the list.
@MainActor
struct SectionEditorPopover: View {
    @Environment(\.dismiss) private var dismiss

    let currentName: String
    let onRename: (String) -> Void
    let onManageNames: () -> Void

    @State private var library = SectionNameLibrary.shared
    @State private var isRenaming = false
    @State private var customName = ""
    @FocusState private var isRenameFocused: Bool

    private static let width: CGFloat = 220
    private static let maxListHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(library.names, id: \.self) { name in
                        SectionEditorMenuRow(title: name, isChecked: name == currentName) {
                            commit(name)
                        }
                    }
                }
            }
            .frame(maxHeight: Self.maxListHeight)
            .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, AppSpacing.xxs)

            renameRow

            Divider()
                .padding(.vertical, AppSpacing.xxs)

            SectionEditorMenuRow(title: "Edit Section List…") {
                dismiss()
                onManageNames()
            }
        }
        .padding(AppSpacing.compact)
        .frame(width: Self.width)
    }

    @ViewBuilder
    private var renameRow: some View {
        if isRenaming {
            TextField("Section name", text: $customName)
                .textFieldStyle(.roundedBorder)
                .focused($isRenameFocused)
                .onSubmit { commit(customName) }
                .padding(.horizontal, AppSpacing.xxs)
                .onAppear { isRenameFocused = true }
        } else {
            SectionEditorMenuRow(title: "Rename…") {
                customName = currentName
                isRenaming = true
            }
        }
    }

    private func commit(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed != currentName {
            onRename(trimmed)
        }
        dismiss()
    }
}

/// A full-width row that highlights under the pointer, like an item in a system menu.
private struct SectionEditorMenuRow: View {
    let title: String
    var isChecked = false
    let action: () -> Void

    @State private var isHovered = false

    private static let checkmarkWidth: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: "checkmark")
                    .font(AppTypography.captionEmphasized)
                    .frame(width: Self.checkmarkWidth)
                    .opacity(isChecked ? 1 : 0)
                Text(title)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? AppColors.textOnFill : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.xxs)
            .padding(.vertical, AppSpacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.xxs, style: .continuous)
                    .fill(isHovered ? AppColors.accentFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
