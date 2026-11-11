import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// Gives the top pane of a `VSplitView` (see
/// `LivePlaybackView.playbackMainSection`) a reasonable initial/minimum
/// height. The actual live-resize measurement happens inside
/// `LiveSetlistWaveformScrollView` itself (it self-measures rather than
/// having an ancestor derive its height and republish it downward, which
/// only works if every view in between is already flexible).
struct LiveSetlistWaveformResizablePane<Content: View>: View {
    var maxMIDILaneCount: Int = 0
    @ViewBuilder let content: () -> Content

    @AppStorage(LiveSetlistWaveformMetrics.appStorageKey)
    private var storedWaveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeightStorageValue
    /// Briefly holds the pane open at the saved waveform height plus MIDI rows.
    /// The split view ignores a later `idealHeight`, but it will honor a minimum
    /// that's taller than the current divider position.
    @State private var reservesMIDILaneHeight = false
    @State private var midiReserveGeneration = 0

    private var overheadHeight: CGFloat {
        LiveSetlistWaveformMetrics.midiLanesHeight(forRowCount: maxMIDILaneCount)
    }

    private var storedContentHeight: CGFloat {
        LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight)
    }

    private var minimumPaneHeight: CGFloat {
        let base = LiveSetlistWaveformMetrics.minimumWaveformHeight + overheadHeight
        guard let reserved = LiveSetlistWaveformPaneAdjustment.reservedPaneHeight(
            storedWaveformHeight: storedContentHeight,
            midiOverhead: overheadHeight,
            isReserving: reservesMIDILaneHeight
        ) else {
            return base
        }
        return max(base, reserved)
    }

    var body: some View {
        content()
            .frame(
                minHeight: minimumPaneHeight,
                idealHeight: storedContentHeight + overheadHeight,
                maxHeight: LiveSetlistWaveformMetrics.maximumWaveformHeight + overheadHeight
            )
            // Keeps the VSplitView divider from sitting flush against the waveform.
            .padding(.bottom, AppSpacing.xs)
            .animation(.none, value: reservesMIDILaneHeight)
            .animation(.none, value: overheadHeight)
            .onAppear {
                reserveSpaceForMIDILanes()
            }
            .onChange(of: overheadHeight) { _, _ in
                reserveSpaceForMIDILanes()
            }
    }

    private func reserveSpaceForMIDILanes() {
        guard overheadHeight > 0.5 else { return }
        midiReserveGeneration += 1
        let generation = midiReserveGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reservesMIDILaneHeight = true
        }
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard generation == midiReserveGeneration else { return }
            var clear = Transaction()
            clear.disablesAnimations = true
            withTransaction(clear) {
                reservesMIDILaneHeight = false
            }
        }
    }
}
#endif
