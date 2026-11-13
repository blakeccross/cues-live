import SwiftUI

#if os(macOS)
/// Waveform strip above the setlist with a drag handle along its bottom edge.
/// Owns the waveform height, saves it, and passes it to the strip through
/// `liveSetlistWaveformHeight`. MIDI lanes add their own height on top.
struct LiveSetlistWaveformResizablePane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @AppStorage(LiveSetlistWaveformMetrics.appStorageKey)
    private var storedWaveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeightStorageValue
    @State private var waveformHeight = LiveSetlistWaveformMetrics.defaultWaveformHeight

    var body: some View {
        VStack(spacing: 0) {
            content()
                .environment(\.liveSetlistWaveformHeight, waveformHeight)
                .padding(.bottom, AppSpacing.xs)

            AppResizableDivider(
                length: $waveformHeight,
                edge: .bottom,
                clamp: LiveSetlistWaveformMetrics.clampedWaveformHeight,
                accessibilityLabel: "Waveform height",
                adjustmentStep: 8,
                onResizeEnded: persistWaveformHeight
            )
            // Above the setlist, so the lower half of the hit area still receives drags.
            .zIndex(1)
        }
        .animation(.none, value: waveformHeight)
        .onAppear {
            waveformHeight = LiveSetlistWaveformMetrics.waveformHeight(fromStorage: storedWaveformHeight)
        }
    }

    private func persistWaveformHeight() {
        storedWaveformHeight = LiveSetlistWaveformMetrics.storageValue(forHeight: waveformHeight)
    }
}
#endif
