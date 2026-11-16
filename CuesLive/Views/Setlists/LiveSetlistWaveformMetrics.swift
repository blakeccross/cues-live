import SwiftUI

enum LiveSetlistWaveformMetrics {
    static let appStorageKey = "liveSetlistWaveformHeight"
    #if os(iOS)
    /// iOS has no resize handle above the setlist, so the height is fixed: a little taller on
    /// iPad, where there's room for it.
    static let defaultWaveformHeight: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 132 : 96
    #else
    static let defaultWaveformHeight: CGFloat = 96
    #endif
    static let defaultWaveformHeightStorageValue = Double(defaultWaveformHeight)
    static let minimumWaveformHeight: CGFloat = 56
    static let maximumWaveformHeight: CGFloat = 200
    static let laneVerticalPadding: CGFloat = 0

    static let horizontalZoomAppStorageKey = "liveSetlistWaveformHorizontalZoom"
    static let defaultHorizontalZoom: CGFloat = 1
    static let defaultHorizontalZoomStorageValue = Double(defaultHorizontalZoom)
    static let minimumHorizontalZoom: CGFloat = 1
    static let maximumHorizontalZoom: CGFloat = 3

    /// Named coordinate space of the strip's content, where lane frames are measured.
    static let scrollCoordinateSpaceName = "live-waveform-scroll"
    static let playheadWidth: CGFloat = 2
    /// Re-enable follow when the playhead is this close to the viewport center.
    static let followRelatchDistance: CGFloat = 64

    /// Height of one MIDI device lane row below the waveform.
    static let midiLaneRowHeight: CGFloat = 18
    static let midiLaneRowSpacing: CGFloat = 3

    static func midiLanesHeight(forRowCount count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * midiLaneRowHeight + CGFloat(count) * midiLaneRowSpacing
    }

    static func clampedWaveformHeight(_ height: CGFloat) -> CGFloat {
        min(maximumWaveformHeight, max(minimumWaveformHeight, height))
    }

    static func waveformHeight(fromStorage value: Double) -> CGFloat {
        clampedWaveformHeight(CGFloat(value))
    }

    static func storageValue(forHeight waveformHeight: CGFloat) -> Double {
        Double(clampedWaveformHeight(waveformHeight))
    }

    static func laneHeight(for waveformHeight: CGFloat) -> CGFloat {
        clampedWaveformHeight(waveformHeight) + laneVerticalPadding
    }

    static func clampedHorizontalZoom(_ zoom: CGFloat) -> CGFloat {
        min(maximumHorizontalZoom, max(minimumHorizontalZoom, zoom))
    }

    static func horizontalZoom(fromStorage value: Double) -> CGFloat {
        clampedHorizontalZoom(CGFloat(value))
    }

    static func storageValue(forZoom horizontalZoom: CGFloat) -> Double {
        Double(clampedHorizontalZoom(horizontalZoom))
    }

    /// Width of a song lane whose waveform snapshot has not loaded yet.
    static let unloadedLaneWidth: CGFloat = 180

    /// Strip across the top of a lane that holds the section markers. Lanes without sections omit it.
    static let sectionRibbonHeight: CGFloat = 22

    /// Waveform ahead of the playhead.
    static let waveformUnplayedOpacity: CGFloat = 0.28
    /// Waveform the playhead has passed.
    static let waveformPlayedOpacity: CGFloat = 0.92
    /// Songs other than the current one are dimmed.
    static let nonCurrentLaneOpacity: CGFloat = 0.72

    /// Bar lines. Drawn with a difference blend over the waveform, so these read as light lines on
    /// the background and dark lines through the waveform.
    static let downbeatTickOpacity: CGFloat = 0.16
    /// Quarter-note (or meter beat) ticks.
    static let beatTickOpacity: CGFloat = 0.07
    /// Halfway between beats. Fainter than the beat.
    static let subdivisionTickOpacity: CGFloat = 0.035
    static let beatGridMaximumDuration: TimeInterval = 10 * 60
    static let minimumBeatTickSpacing: CGFloat = 8
    static let minimumSubdivisionTickSpacing: CGFloat = 6
}

private struct LiveSetlistWaveformHeightKey: EnvironmentKey {
    static let defaultValue = LiveSetlistWaveformMetrics.defaultWaveformHeight
}

extension EnvironmentValues {
    var liveSetlistWaveformHeight: CGFloat {
        get { self[LiveSetlistWaveformHeightKey.self] }
        set { self[LiveSetlistWaveformHeightKey.self] = newValue }
    }
}
