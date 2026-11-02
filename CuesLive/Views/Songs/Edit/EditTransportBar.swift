import SwiftData
import SwiftUI

struct EditTransportBar<Chrome: View>: View {
    let viewModel: SongEditorViewModel
    let markers: [ArrangementMarker]
    @Bindable var song: Song
    @Binding var showingArrangementEditor: Bool
    @Binding var showingTimeSignatureEditor: Bool
    @Binding var timeSignatureChanges: [TimeSignatureChange]
    let normalizedTimeSignatureChanges: [TimeSignatureChange]
    let onPersistTimeSignatureChanges: () -> Void
    @Binding var tempoChanges: [TempoChange]
    let normalizedTempoChanges: [TempoChange]
    let onApplyTempo: (Double) -> Void
    let onApplyBaseKey: (String?) -> Void
    @Binding var showingChangeKey: Bool
    @Binding var arrangementSlots: [ArrangementSlot]
    @Binding var clipTrims: [ArrangementClipTrim]
    @Binding var removedClips: [ArrangementRemovedClip]
    @Binding var clipGaps: [ArrangementClipGap]
    @Binding var clipRegions: [ClipRegion]
    @Binding var loopSlotIDs: Set<UUID>
    @Binding var showingSongLibrary: Bool
    @Binding var showingBakeSheet: Bool
    @Binding var showingGroupEditor: Bool
    let isDetectingSections: Bool
    let onDetectSections: () -> Void
    let onClearMarkerCue: () -> Void
    let onPersistArrangement: () -> Void
    let onUndoableChange: UndoableChangeHandler
    let captureSnapshot: () -> SongEditSnapshot
    let currentSectionAtTime: (TimeInterval) -> ArrangementDisplaySection?
    let onStopTransport: () -> Void
    let onToggleLoopAtTime: (TimeInterval) -> Void
    let registerUndo: (_ actionName: String, _ before: SongEditSnapshot, _ after: SongEditSnapshot) -> Void
    let onBack: () -> Void
    let undoController: SongUndoController
    let content: Chrome

    @State private var showingTempoToolbarEditor = false
    @State private var showingKeyToolbarEditor = false
    @State private var showingClickEditor = false
    @State private var showingSmartGuideEditor = false
    @State private var groupMixFade = GroupMixFadeController()
    @Bindable private var audioEngine = AudioEngineManager.shared
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(AppColors.surfaceElevated)
            }
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiveTransportBottomBar {
                transportCluster
            }
        }
        #if os(iOS)
        .toolbar {
            editorToolbar
        }
        #endif
        .sheet(isPresented: $showingClickEditor) {
            ClickTrackEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                chrome: .sheet
            )
        }
        .sheet(isPresented: $showingSmartGuideEditor) {
            SmartGuideEditorButton(
                song: song,
                viewModel: viewModel,
                captureSnapshot: captureSnapshot,
                registerUndo: registerUndo,
                chrome: .sheet
            )
        }
        .sheet(isPresented: $showingArrangementEditor) {
            ArrangementEditorMenu(
                slots: $arrangementSlots,
                clipTrims: $clipTrims,
                removedClips: $removedClips,
                clipGaps: $clipGaps,
                clipRegions: $clipRegions,
                loopSlotIDs: $loopSlotIDs,
                markers: markers,
                onPersist: onPersistArrangement,
                onUndoableChange: onUndoableChange
            )
            .padding(AppSpacing.md)
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            backButton
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                undoController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!undoController.canUndo)
            .accessibilityLabel(undoController.undoActionName.map { "Undo \($0)" } ?? "Undo")

            Button {
                undoController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!undoController.canRedo)
            .accessibilityLabel(undoController.redoActionName.map { "Redo \($0)" } ?? "Redo")

            overflowMenu
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                showingChangeKey = true
            } label: {
                Label("Change Key", systemImage: "key")
            }
            .disabled(song.sortedTracks.isEmpty)

            Button {
                showingClickEditor = true
            } label: {
                Label("Click Track", systemImage: "metronome")
            }

            Button {
                showingSmartGuideEditor = true
            } label: {
                Label("Smart Guide", systemImage: "person.wave.2")
            }

            if !markers.isEmpty {
                Button {
                    showingArrangementEditor = true
                } label: {
                    Label("Arrangement", systemImage: "list.bullet.rectangle")
                }
            }

            Divider()

            if SongSectionDetector.isAvailable {
                Button {
                    onDetectSections()
                } label: {
                    Label(isDetectingSections ? "Detecting Sections…" : "Detect Sections", systemImage: "wand.and.stars")
                }
                .disabled(isDetectingSections || SongSectionDetector.analysisTracks(in: song).isEmpty)
            }

            Button("Manage Groups…") {
                showingGroupEditor = true
            }

            Button("Bake Tracks…") {
                showingBakeSheet = true
            }
            .disabled(song.sortedTracks.isEmpty)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label("Back", systemImage: "chevron.backward")
                .labelStyle(.iconOnly)
        }
        .help("Back")
    }
    #endif

    private var transportCluster: some View {
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
        let snapshot = displaySnapshot(at: time)

        return SharedTransportStrip(
            snapshot: snapshot,
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
        return loopSlotIDs.contains(section.id)
    }

}
