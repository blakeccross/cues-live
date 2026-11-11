import SwiftUI

/// Title and time editor shared by local and remote header creation.
struct SetlistHeaderEditorSheet: View {
    let navigationTitle: String
    let confirmTitle: String
    @Binding var headerTitle: String
    @Binding var timeSeconds: TimeInterval
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var canConfirm: Bool {
        !headerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            editorContent
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle, action: onConfirm)
                        .disabled(!canConfirm)
                }
            }
        }
        .standardDialogToolbar()
    }

    private var editorContent: some View {
        headerForm
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, idealWidth: 460)
            #endif
    }

    private var headerForm: some View {
        Form {
            Section {
                TextField("Title", text: $headerTitle)
                #if os(macOS)
                LabeledContent {
                    SetlistHeaderDurationField(seconds: $timeSeconds)
                        .alignmentGuide(VerticalAlignment.center) { _ in
                            SetlistHeaderDurationField.macBezelHeight / 2
                        }
                } label: {
                    Text("Duration")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, -10)
                #else
                SetlistHeaderDurationField(seconds: $timeSeconds)
                #endif
            } footer: {
                Text(durationFooter)
            }
        }
    }

    private var durationFooter: String {
        #if os(macOS)
        "Shown beside the header, like a song length."
        #else
        "Headers divide the setlist into sections. The duration is shown in the same column as song durations."
        #endif
    }
}
