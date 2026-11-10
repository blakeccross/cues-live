import SwiftUI
import UniformTypeIdentifiers

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

/// Audio files dragged onto the song editor. Each one lands on a new track at the
/// edit insertion; the editor reads the files here and the caller does the placement.
enum AudioFileDrop {
    struct OpenedFile {
        let url: URL
        let scoped: Bool

        func close() {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    static func openAudioFiles(from providers: [NSItemProvider]) async -> [OpenedFile] {
        var opened: [OpenedFile] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            guard let url = await loadFileURL(from: provider), FileStore.isSupportedAudioFile(url) else { continue }
            opened.append(OpenedFile(url: url, scoped: url.startAccessingSecurityScopedResource()))
        }
        return opened
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL:
                    continuation.resume(returning: url)
                case let data as Data:
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Accepts a Finder drag of audio files. The outline shows while the drag is over the editor.
struct AudioFileDropModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    func body(content: Content) -> some View {
        content
        #if os(macOS)
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColors.accent, lineWidth: 2)
                    .padding(AppSpacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], delegate: AudioFileDropDelegate(
            onHover: { isTargeted = $0 },
            onPerform: onDrop
        ))
        #endif
    }
}

#if os(macOS)
private struct AudioFileDropDelegate: DropDelegate {
    let onHover: (Bool) -> Void
    let onPerform: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        onHover(true)
    }

    func dropExited(info: DropInfo) {
        onHover(false)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        onHover(false)
        return onPerform(info.itemProviders(for: [.fileURL]))
    }
}
#endif
