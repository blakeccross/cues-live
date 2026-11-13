import SwiftUI

extension EditView {
    /// Runs a key or MIDI mapping. Only transport actions apply inside the editor;
    /// song and section jumps belong to the setlist.
    func handleMappedLiveAction(_ action: MappableLiveAction) {
        guard viewModel.isLoaded else { return }
        switch action {
        case .stop:
            stopTransport()
        case .playPause:
            if audioEngine.isPlaying {
                viewModel.pause()
            } else {
                playFromInsertion()
            }
        case .fade:
            toggleGroupMixFade()
        case .loop:
            toggleLoop(at: audioEngine.isPlaying ? audioEngine.currentTime : playbackStart)
        case .goToSong, .goToSection:
            break
        }
    }

    func stopTransport() {
        groupMixFade.clearFade(context: modelContext) {
            audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
            try? modelContext.save()
        }
        clearMarkerCue()
        viewModel.stop()
    }

    func toggleGroupMixFade() {
        groupMixFade.toggleFade(context: modelContext) {
            audioEngine.applyGroupMix(GroupMixStore.snapshot(in: modelContext))
        } onComplete: {
            try? modelContext.save()
        }
    }

    func toggleLoop(at time: TimeInterval) {
        guard let section = displaySections.section(atTimeline: time) else { return }
        toggleLoopSection(section)
    }
}
