import SwiftUI

struct RenameSectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var title: String = "Rename Section"
    let currentName: String
    let onRename: (String) -> Void

    @State private var customName: String = ""
    @FocusState private var customFieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: AppSpacing.xs)]

    private var trimmedCustomName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(SongSectionPresets.groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppColors.textSecondary)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.xs) {
                                    ForEach(group.options, id: \.self) { option in
                                        AppChip(title: option, isSelected: option == currentName) {
                                            commit(option)
                                        }
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Custom Name")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColors.textSecondary)

                            HStack(spacing: AppSpacing.sm) {
                                TextField("Section name", text: $customName)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($customFieldFocused)
                                    .onSubmit {
                                        if !trimmedCustomName.isEmpty {
                                            commit(trimmedCustomName)
                                        }
                                    }

                                AppSecondaryButton(title: "Use", isEnabled: !trimmedCustomName.isEmpty) {
                                    commit(trimmedCustomName)
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                }
                .frame(minWidth: 380, minHeight: 360)
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    customName = currentName
                }
            }
        }
    }

    private func commit(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        dismiss()
    }
}
