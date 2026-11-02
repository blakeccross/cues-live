import SwiftUI

enum AddTrackKind: CaseIterable, Identifiable {
    case audio
    case midi
    case ableton

    var id: Self { self }

    var title: String {
        switch self {
        case .audio: "Track"
        case .midi: "MIDI"
        case .ableton: "Ableton File"
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "waveform"
        case .midi: "pianokeys"
        case .ableton: "doc"
        }
    }

    var subtitle: String {
        switch self {
        case .audio: "Import audio stems"
        case .midi: "Add a MIDI lane"
        case .ableton: "Import sections and tempo"
        }
    }
}

struct AddTrackTypeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onChoose: (AddTrackKind) -> Void

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                List {
                    Section {
                        ForEach(AddTrackKind.allCases) { kind in
                            Button {
                                onChoose(kind)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(kind.title)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Text(kind.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                } icon: {
                                    Image(systemName: kind.systemImage)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Add Track")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280)
    }
}

struct AddTrackFlowModifier: ViewModifier {
    @Binding var showingTrackImporter: Bool
    @Binding var showingAbletonImporter: Bool
    @Binding var importError: String?
    @Binding var abletonImportSummary: String?
    let onImportTracks: (Result<[URL], Error>) -> Void
    let onImportAbleton: (Result<[URL], Error>) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $showingTrackImporter,
                allowedContentTypes: FileStore.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                onImportTracks(result)
            }
            .fileImporter(
                isPresented: $showingAbletonImporter,
                allowedContentTypes: [AbletonProjectImporter.abletonLiveSetType],
                allowsMultipleSelection: false
            ) { result in
                onImportAbleton(result)
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert("Ableton Import Complete", isPresented: Binding(
                get: { abletonImportSummary != nil },
                set: { if !$0 { abletonImportSummary = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(abletonImportSummary ?? "")
            }
    }
}
