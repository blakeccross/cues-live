import SwiftData
import SwiftUI

/// The Smart Guide settings shown in a sheet; everything changed while it is open is one undo step.
struct SmartGuideEditorSheet: View {
    @Bindable var song: Song
    let viewModel: SongEditorViewModel
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void

    @State private var editStartSnapshot: SongEditSnapshot?

    var body: some View {
        SmartGuideMenu(song: song, viewModel: viewModel)
            .onAppear {
                editStartSnapshot = captureSnapshot()
            }
            .onDisappear(perform: commitUndoIfNeeded)
    }

    private func commitUndoIfNeeded() {
        guard let before = editStartSnapshot else { return }
        let after = captureSnapshot()
        if before != after {
            registerUndo("Smart Guide", before, after)
        }
        editStartSnapshot = nil
    }
}

struct SmartGuideMenu: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var song: Song
    let viewModel: SongEditorViewModel

    /// A "Cues" track baked by an earlier version would double every callout.
    private var legacyCuesTrack: AudioTrack? {
        song.sortedTracks.first {
            $0.displayName.caseInsensitiveCompare(TrackGroupStore.guideGroupName) == .orderedSame
        }
    }

    private var sectionNames: [String] {
        var seen = Set<String>()
        return SongProjectBridge.projectStateOrDefaults(for: song).markers
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var sectionsWithoutVoice: [String] {
        sectionNames.filter { !SpeechSampleRenderer.hasSample(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Smart Guide")
                .font(AppTypography.headline)

            Toggle("Call out sections", isOn: $song.smartGuideEnabled)
                .toggleStyle(.switch)

            Text("A voice calls each section one measure before it starts, and calls a looping section on every pass. Cueing a section too late skips the call. Plays through the Cues output.")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if song.smartGuideEnabled, let cuesTrack = legacyCuesTrack, !cuesTrack.isMuted {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("This song has a baked Cues track, so callouts would play twice.")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mute Cues Track") {
                        cuesTrack.isMuted = true
                        viewModel.updateMix(for: cuesTrack, context: modelContext)
                    }
                }
            }

            if song.smartGuideEnabled, !sectionsWithoutVoice.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Label("No voice for:", systemImage: "exclamationmark.triangle")
                        .font(AppTypography.captionEmphasized)
                        .foregroundStyle(AppColors.warning)
                    Text(sectionsWithoutVoice.joined(separator: ", "))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("These sections will not be called. Rename them to a standard section name to hear them.")
                        .font(AppTypography.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
        .onChange(of: song.smartGuideEnabled) { _, _ in
            try? modelContext.save()
            try? SongProjectBridge.syncProjectFile(for: song, context: modelContext)
        }
    }
}
