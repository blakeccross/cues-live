import SwiftUI

/// Edits the section names offered when naming a marker: add, rename, reorder, and remove.
@MainActor
struct SectionNameListEditorView: View {
    enum Presentation {
        case sheet
        case settings
    }

    @Environment(\.dismiss) private var dismiss

    var presentation: Presentation = .sheet

    @State private var library = SectionNameLibrary.shared
    @State private var newName = ""
    @State private var nameError: String?

    private static let sheetMinWidth: CGFloat = 400
    private static let sheetMinHeight: CGFloat = 520

    var body: some View {
        switch presentation {
        case .sheet:
            AppSheetContainer {
                NavigationStack {
                    editorList
                        .navigationTitle("Section Names")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
            #if os(macOS)
            .frame(minWidth: Self.sheetMinWidth, minHeight: Self.sheetMinHeight)
            #endif
        case .settings:
            editorList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorList: some View {
        Form {
            Section {
                ForEach(Array(library.names.enumerated()), id: \.element) { index, name in
                    SectionNameRow(name: name, index: index, library: library, onNameError: { nameError = $0 })
                }
                .onMove { library.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { library.remove(atOffsets: $0) }
            } footer: {
                Text("These names appear when you double-click a section marker. Drag to reorder.")
            }

            Section {
                TextField("New Section Name", text: $newName)
                    .onSubmit(addName)
                Button("Add Section Name", action: addName)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                if let nameError {
                    Text(nameError)
                        .foregroundStyle(AppColors.error)
                }
            }

            Section {
                Button("Restore Defaults", role: .destructive) {
                    library.restoreDefaults()
                    nameError = nil
                }
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
    }

    private func addName() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard library.add(trimmed) else {
            nameError = "That section name is already in the list."
            return
        }
        newName = ""
        nameError = nil
    }
}

/// One editable name. Commits when Return is pressed or focus leaves the field.
private struct SectionNameRow: View {
    let name: String
    let index: Int
    let library: SectionNameLibrary
    let onNameError: (String?) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            TextField("Section Name", text: $draft)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit(commit)
            #if os(macOS)
            Button {
                library.remove(atOffsets: [index])
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove \(name)")
            #endif
        }
        .onAppear { draft = name }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != name else { return }
        if library.rename(at: index, to: trimmed) {
            onNameError(nil)
        } else {
            draft = name
            onNameError(trimmed.isEmpty ? "Section name cannot be empty." : "That section name is already in the list.")
        }
    }
}
