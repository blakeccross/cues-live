import SwiftUI


struct LiveSetlistAddMenu: View {
    /// iOS only: shows an Edit/Done button that toggles drag-to-reorder. Pass nil when there is nothing to edit.
    var isEditing: Binding<Bool>? = nil
    var onAddHeader: () -> Void
    var onAddSong: () -> Void

    var body: some View {
        HStack {
            #if os(iOS)
            if let isEditing {
                Button(isEditing.wrappedValue ? "Done" : "Edit") {
                    withAnimation { isEditing.wrappedValue.toggle() }
                }
                .font(.body)
                .accessibilityLabel(isEditing.wrappedValue ? "Done reordering" : "Edit setlist order")
            }
            #endif

            Spacer(minLength: 0)

            Menu {
                Button(action: onAddHeader) {
                    Label("Header", systemImage: "text.line.first.and.arrowtriangle.forward")
                }

                Button(action: onAddSong) {
                    Label("Song", systemImage: "music.note")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .fixedSize()
            .setlistMenuFittedSizing()
            .appLinkPointer()
            .accessibilityLabel("Add to setlist")
            .help("Add to Setlist")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
    }
}

extension View {
    /// iOS 26+ Menu defaults to flexible (full-width) button sizing.
    @ViewBuilder
    func setlistMenuFittedSizing() -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            buttonSizing(.fitted)
        } else {
            self
        }
    }
}
