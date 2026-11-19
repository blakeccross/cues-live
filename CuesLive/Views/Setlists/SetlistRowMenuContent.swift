import SwiftUI

/// The single source of truth for row actions: used by the context menu and the "…" button.
struct SetlistRowMenuContent: View {
    let model: SetlistRowModel
    let actions: SetlistRowActions
    /// Nil when the song has no sections to show.
    var sectionsExpanded: Binding<Bool>? = nil
    let remove: () -> Void

    var body: some View {
        if let cue = actions.cue {
            Button(action: cue) {
                Label("Cue", systemImage: "forward.end.fill")
            }
        }

        if let sectionsExpanded {
            let isExpanded = sectionsExpanded.wrappedValue
            Button {
                withAnimation(AppAnimation.springSnappy) {
                    sectionsExpanded.wrappedValue.toggle()
                }
            } label: {
                Label(
                    isExpanded ? "Hide Sections" : "Show Sections",
                    systemImage: isExpanded ? "list.bullet.indent" : "list.bullet"
                )
            }
        }

        if case .song(let song) = model.kind,
           let current = song.transition,
           let setTransition = actions.setTransition,
           !actions.transitions.isEmpty {
            Menu {
                ForEach(actions.transitions) { option in
                    Button {
                        setTransition(option)
                    } label: {
                        Label(option.label, systemImage: option == current ? "checkmark" : option.systemImage)
                    }
                }
            } label: {
                Label("Transition to Next", systemImage: current.systemImage)
            }
        }

        if let edit = actions.edit {
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
            }
        }

        if let relink = actions.relink {
            Button(action: relink) {
                Label("Relink Missing Files…", systemImage: "exclamationmark.triangle")
            }
        }

        Button(role: .destructive, action: remove) {
            Label("Remove from Setlist", systemImage: "trash")
        }
    }
}
