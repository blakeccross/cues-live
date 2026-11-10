import SwiftData
import SwiftUI

struct EditTransportStatusStrip: View {
    let viewModel: SongEditorViewModel

    var body: some View {
        Group {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(AppColors.surfaceElevated)
    }
}

#if os(macOS)
struct EditSongTransportCluster: View {
    let viewModel: SongEditorViewModel
    @Bindable var song: Song
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    let normalizedTimeSignatureChanges: [TimeSignatureChange]
    let onPersistTimeSignatureChanges: () -> Void
    let normalizedTempoChanges: [TempoChange]
    let onApplyTempo: (Double) -> Void
    let onApplyBaseKey: (String?) -> Void
    @Binding var showingTimeSignatureEditor: Bool
    let loopSectionIDs: Set<UUID>
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void

    @State private var showingTempoToolbarEditor = false
    @State private var showingKeyToolbarEditor = false
    @State private var groupMixFade = GroupMixFadeController()
    @Bindable private var audioEngine = AudioEngineManager.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if audioEngine.isPlaying {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { _ in
                    transportStrip(at: audioEngine.currentTime)
                }
            } else {
                transportStrip(at: audioEngine.currentTime)
            }
        }
    }

    private func transportStrip(at time: TimeInterval) -> some View {
        SharedTransportStrip(
            snapshot: displaySnapshot(at: time),
            buttonSize: 44,
            isPlaying: audioEngine.isPlaying,
            isLoaded: viewModel.isLoaded,
            isLooping: sectionLoopIsActive(at: time),
            canLoop: currentSectionAtTime(time) != nil,
            onStop: {
                groupMixFade.clearFade(context: modelContext) {
                    audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
                    try? modelContext.save()
                }
                onStopTransport()
            },
            onPlay: viewModel.play,
            onPause: viewModel.pause,
            onToggleLoop: { onToggleLoopAtTime(time) },
            isFadedOut: groupMixFade.isFadedOut,
            isFading: groupMixFade.isFading,
            onToggleFade: {
                groupMixFade.toggleFade(context: modelContext) {
                    audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
                } onComplete: {
                    try? modelContext.save()
                }
            },
            showingBPMPopover: $showingTempoToolbarEditor,
            showingMeterPopover: $showingTimeSignatureEditor,
            showingKeyPopover: $showingKeyToolbarEditor,
            bpmPopover: {
                TempoEditorMenu(
                    currentBPM: normalizedTempoChanges.referenceBPM,
                    onApply: onApplyTempo
                )
            },
            meterPopover: {
                TimeSignatureEditorMenu(
                    song: song,
                    timeSignatureChanges: $timeSignatureChanges,
                    normalizedTimeSignatureChanges: normalizedTimeSignatureChanges,
                    onPersist: onPersistTimeSignatureChanges
                )
            },
            keyPopover: {
                SongKeyEditorMenu(
                    baseKeyRaw: song.baseKeyRaw,
                    onApply: onApplyBaseKey
                )
            }
        )
    }

    private func displaySnapshot(at time: TimeInterval) -> TransportStatusSnapshot {
        let position = MeasureTiming.position(
            at: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )
        let signature = MeasureTiming.numeratorDenominatorForMeasure(
            position.bar,
            changes: normalizedTimeSignatureChanges
        )
        let bpm = MeasureTiming.activeBPM(
            at: time,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges
        )

        return TransportStatusSnapshot(
            position: MeasureTiming.formatTransportPosition(position),
            bpm: String(format: "%.1f", bpm),
            meter: "\(signature.numerator)/\(signature.denominator)",
            key: song.transportKeyText
        )
    }

    private func sectionLoopIsActive(at time: TimeInterval) -> Bool {
        guard let section = currentSectionAtTime(time) else { return false }
        return loopSectionIDs.contains(section.id)
    }
}

struct EditSongToolbarContent: ToolbarContent {
    let viewModel: SongEditorViewModel
    @Bindable var song: Song
    @Binding var showingArrangementEditor: Bool
    @Binding var showingTimeSignatureEditor: Bool
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    let normalizedTimeSignatureChanges: [TimeSignatureChange]
    let onPersistTimeSignatureChanges: () -> Void
    let normalizedTempoChanges: [TempoChange]
    let onApplyTempo: (Double) -> Void
    let onApplyBaseKey: (String?) -> Void
    let arrangementActions: ArrangementSectionActions
    let loopSectionIDs: Set<UUID>
    @Binding var showingSongLibrary: Bool
    @Binding var showingGroupEditor: Bool
    let isDetectingSections: Bool
    let onDetectSections: () -> Void
    let onBack: () -> Void
    let currentSectionAtTime: (TimeInterval) -> SongSection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let captureSnapshot: () -> SongEditSnapshot
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onClickTrackGenerated: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            backButton
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .principal) {
            if LiveTransportLayout.macOSPlacesControlsAtBottom {
                LiveToolbarSongTitle(title: song.name, upNext: nil)
            } else {
                editorTransportCluster
            }
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            ClickTrackEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                onClickTrackGenerated: onClickTrackGenerated
            )
        }
        .cuesHideSharedBackground()

        ToolbarItem(placement: .automatic) {
            SmartGuideEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo
            )
        }
        .cuesHideSharedBackground()

        if !arrangementActions.sections.isEmpty {
            ToolbarItem(placement: .automatic) {
                arrangementEditorButton
            }
            .cuesHideSharedBackground()
        }

        ToolbarItem(placement: .automatic) {
            moreMenu
        }
        .cuesHideSharedBackground()
    }

    private var editorTransportCluster: some View {
        EditSongTransportCluster(
            viewModel: viewModel,
            song: song,
            timeSignatureChanges: $timeSignatureChanges,
            normalizedTimeSignatureChanges: normalizedTimeSignatureChanges,
            onPersistTimeSignatureChanges: onPersistTimeSignatureChanges,
            normalizedTempoChanges: normalizedTempoChanges,
            onApplyTempo: onApplyTempo,
            onApplyBaseKey: onApplyBaseKey,
            showingTimeSignatureEditor: $showingTimeSignatureEditor,
            loopSectionIDs: loopSectionIDs,
            currentSectionAtTime: currentSectionAtTime,
            onStopTransport: onStopTransport,
            onToggleLoopAtTime: onToggleLoopAtTime
        )
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.backward")
                .labelStyle(.iconOnly)
        }
        .help("Back")
    }

    private var arrangementEditorButton: some View {
        Button {
            showingArrangementEditor = true
        } label: {
            Label("Arrangement", systemImage: "list.bullet.rectangle")
                .labelStyle(.iconOnly)
        }
        .help("Arrangement")
        .popover(isPresented: $showingArrangementEditor, arrowEdge: .bottom) {
            ArrangementEditorMenu(actions: arrangementActions)
        }
    }

    private var moreMenu: some View {
        Menu {
            if SongSectionDetector.isAvailable {
                Button(isDetectingSections ? "Detecting Sections…" : "Detect Sections") {
                    onDetectSections()
                }
                .disabled(isDetectingSections || SongSectionDetector.analysisTracks(in: song).isEmpty)
                Divider()
            }
            Button("Manage Groups…") {
                showingGroupEditor = true
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .help("More")
    }
}
#endif

struct DetectSectionsFlowModifier: ViewModifier {
    @Binding var showingReplaceConfirm: Bool
    @Binding var error: String?
    let onConfirmReplace: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Replace existing sections?",
                isPresented: $showingReplaceConfirm,
                titleVisibility: .visible
            ) {
                Button("Replace Sections", role: .destructive, action: onConfirmReplace)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Detected sections replace the current ones and reset arrangement edits such as reordered, trimmed or looped sections. You can undo this.")
            }
            .alert("Couldn’t Detect Sections", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
    }
}
