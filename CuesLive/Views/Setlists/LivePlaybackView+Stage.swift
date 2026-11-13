import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

extension LivePlaybackView {
    var playbackMainLayout: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            LivePlaybackMixerSplitLayout(
                mixerDetent: $mixerDetent,
                onLiveVolumeChange: { groupID, volume in
                    coordinator.applyProvisionalGroupVolume(groupID: groupID, volume: volume)
                },
                onMixChange: {
                    coordinator.updateGroupMix(context: modelContext)
                },
                mainContent: {
                    playbackMainSection
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LiveTransportBottomBar {
                transportStrip
            }
        }
        #else
        playbackMainSection
            .navigationDestination(isPresented: mixerScreenPresented) {
                LiveGroupMixerScreen(
                    onLiveVolumeChange: { groupID, volume in
                        coordinator.applyProvisionalGroupVolume(groupID: groupID, volume: volume)
                    },
                    onMixChange: {
                        coordinator.updateGroupMix(context: modelContext)
                    }
                )
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LiveTransportBottomBar {
                    transportStrip
                }
            }
        #endif
    }

    #if os(iOS)
    private var mixerScreenPresented: Binding<Bool> {
        Binding(
            get: { mixerDetent == .visible },
            set: { mixerDetent = $0 ? .visible : .hidden }
        )
    }
    #endif

    private var transportStrip: some View {
        LiveSetlistNowPlayingInfoView(
            coordinator: coordinator,
            sectionLoop: sectionLoop,
            groupMixFade: groupMixFade,
            isLoaded: coordinator.isLoaded && !coordinator.isLoadingSong,
            canLoop: !loopSections.isEmpty,
            onStop: stopPlayback,
            onPlay: coordinator.play,
            onPause: coordinator.pause,
            onToggleLoop: toggleSectionLoop,
            onToggleFade: toggleGroupMixFade
        )
    }

    func toggleGroupMixFade() {
        groupMixFade.toggleFade(context: modelContext) {
            coordinator.updateGroupMix(context: modelContext, persist: false)
        } onComplete: {
            coordinator.updateGroupMix(context: modelContext)
        }
    }

    func songLibraryPanel() -> some View {
        SongLibraryPanel(
            onEdit: { song in
                presentSongEditor(for: song)
            },
            onDismiss: {
                showingSongLibrary = false
            },
            onFoldersSelected: { requests in
                importSongs(from: requests)
            },
            onAddToSetlist: { song in
                addSong(song, at: workingSetlist.sortedEntries.count)
            },
            isImportInProgress: isImportingSongFolder
        )
    }

    var playbackMonitorSupport: some View {
        LivePlaybackMonitorSupport(
            cuedSectionID: cuedSectionID,
            cueFireTime: cueFireTime,
            onFireMarkerCue: fireMarkerCue,
            smartGuideEnabled: coordinator.currentSong?.smartGuideEnabled ?? false,
            sections: loopSections,
            announcer: sectionAnnouncer,
            sectionLoop: sectionLoop,
            loopSections: loopSections,
            loopSectionIDs: loopSectionIDs,
            playbackEngine: coordinator.playbackEngine,
            onLoopActivated: { clearMarkerCue() }
        )
    }

    private var playbackMainSection: some View {
        #if os(macOS)
        Group {
            if setlistHasSongs {
                VSplitView {
                    currentSongSection
                        .background(AppColors.backgroundPrimary)

                    librarySplitSection
                }
            } else {
                librarySplitSection
            }
        }
        #else
        VStack(spacing: 0) {
            if setlistHasSongs {
                currentSongSection
                    .background(AppColors.backgroundPrimary)
            }

            setlistSection
                .background(AppColors.backgroundPrimary)
        }
        #endif
    }

    #if os(macOS)
    private var librarySplitSection: some View {
        LiveSongLibrarySplitLayout(isLibraryVisible: showingSongLibrary) {
            songLibraryPanel()
        } setlist: {
            setlistSection
                .background(AppColors.backgroundPrimary)
        }
    }
    #endif

    private var currentSongSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            LiveSetlistWaveformResizablePane(maxMIDILaneCount: coordinator.maxMIDILaneCount) {
                waveformContent
                    .padding(.top, AppSpacing.xs)
                    .overlay(alignment: .topLeading) { loadErrorBanner }
            }
            #else
            waveformContent
                .padding(.top, AppSpacing.xs)
                .overlay(alignment: .topLeading) { loadErrorBanner }
            #endif
        }
    }

    /// Overlaid rather than swapped in for the waveform so a failed load keeps the pane's height.
    @ViewBuilder
    private var loadErrorBanner: some View {
        // Missing audio is flagged on the sections themselves, so its load error stays hidden.
        if let loadError = coordinator.loadError,
           !(coordinator.currentSong.map(songHasMissingMedia) ?? false) {
            Label(loadError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                .padding(AppSpacing.md)
        }
    }

    @ViewBuilder
    private var waveformContent: some View {
        if setlistHasSongs {
            LiveSetlistWaveformScrollView(
                timelineItems: coordinator.timelineItems,
                currentPlaybackIndex: coordinator.currentIndex,
                waveformSnapshotForSongID: { songID in
                    guard let song = coordinator.song(for: songID) else { return nil }
                    return coordinator.waveformSnapshot(for: song)
                },
                ensureWaveformSnapshotForSongID: { songID in
                    guard let song = coordinator.song(for: songID) else { return }
                    coordinator.ensureWaveformSnapshot(for: song)
                },
                songHasMissingMedia: { songID in
                    coordinator.song(for: songID).map(songHasMissingMedia) ?? false
                },
                playheadTimeProvider: { coordinator.livePlayheadTime() },
                isPlayingProvider: { coordinator.isPlaying },
                // Only observe clock time while idle so seeks move the marker without
                // rebuilding the setlist on every playhead tick during playback.
                idlePlayheadTime: playbackClock.isPlaying ? nil : playbackClock.currentTime,
                cuedSectionID: cuedSectionID,
                cueFlashPhase: cueFlashPhase,
                onSeek: coordinator.seek,
                onCueSection: cueSection,
                onOverlapBadgeTapped: { playbackIndex in
                    presentOverlapEditor(forPlaybackIndex: playbackIndex)
                },
                onSelectSong: { index, startTime in
                    clearMarkerCue()
                    sectionLoop.endLoopIfActive()
                    coordinator.goToSong(
                        at: index,
                        autoPlay: coordinator.isAudiblePlaying,
                        startTime: startTime
                    )
                },
                maxMIDILaneCount: coordinator.maxMIDILaneCount
            )
            .overlay {
                if coordinator.isLoadingSong {
                    loadingOverlay
                }
            }
        } else if coordinator.isLoadingSong {
            LiveSetlistWaveformLoadingPlaceholder(
                message: "Loading audio…"
            )
        } else {
            LiveSetlistWaveformLoadingPlaceholder()
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
            ProgressView("Loading audio…")
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
