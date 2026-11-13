import SwiftUI

enum ArrangementSectionPalette {
    /// Saturated section fills — clear section identity without overpowering the waveform.
    private static let pairs: [(background: Color, accent: Color)] = [
        (Color(red: 0.10, green: 0.18, blue: 0.34), Color(red: 0.40, green: 0.68, blue: 1.00)),
        (Color(red: 0.28, green: 0.20, blue: 0.06), Color(red: 0.95, green: 0.78, blue: 0.28)),
        (Color(red: 0.30, green: 0.12, blue: 0.06), Color(red: 1.00, green: 0.55, blue: 0.28)),
        (Color(red: 0.30, green: 0.08, blue: 0.16), Color(red: 1.00, green: 0.42, blue: 0.62)),
        (Color(red: 0.04, green: 0.22, blue: 0.22), Color(red: 0.22, green: 0.88, blue: 0.78)),
        (Color(red: 0.16, green: 0.08, blue: 0.32), Color(red: 0.72, green: 0.48, blue: 1.00)),
    ]

    static let backgroundFillOpacity: Double = 0.30
    static let backgroundCueFillOpacity: Double = 0.48

    static func colors(for index: Int) -> (background: Color, accent: Color) {
        pairs[index % pairs.count]
    }
}

enum LiveSetlistWaveformMetrics {
    static let appStorageKey = "liveSetlistWaveformHeight"
    #if os(iOS)
    /// iOS has no resizable split above the setlist, so the height is fixed: a little taller on
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

    /// Waveform ahead of the playhead.
    static let waveformUnplayedOpacity: CGFloat = 0.32
    /// Waveform the playhead has passed. Brighter than the rest, still translucent.
    static let waveformPlayedOpacity: CGFloat = 0.80
    /// Songs other than the current one are dimmed.
    static let nonCurrentLaneOpacity: CGFloat = 0.72

    /// Bar lines. A step down from solid so the waveform stays in front.
    static let downbeatTickOpacity: CGFloat = 0.50
    /// Quarter-note (or meter beat) ticks.
    static let beatTickOpacity: CGFloat = 0.16
    /// Halfway between beats. Fainter than the downbeat.
    static let subdivisionTickOpacity: CGFloat = 0.08
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

/// How the setlist split pane should react when MIDI lanes appear after the
/// divider has already been placed. `VSplitView` keeps that first height, so a
/// later lane row is clipped until the measured waveform height shrinks to
/// make room or the pane's minimum is raised long enough for the divider to move.
enum LiveSetlistWaveformPaneAdjustment {
    struct Measurement: Equatable {
        var assignedHeight: CGFloat
        var midiOverhead: CGFloat
        var storedWaveformHeight: CGFloat
        var previousAssignedHeight: CGFloat?
        var previousMIDIOverhead: CGFloat?
        /// The pane did not grow for the new lanes. Fit them into the height it has.
        var forceFit: Bool = false
    }

    struct Decision: Equatable {
        /// `nil` leaves the current waveform height alone so a pending pane
        /// resize can keep the saved waveform size.
        var waveformHeight: CGFloat?
        var persistWaveformHeight: Bool
    }

    static func decision(for measurement: Measurement) -> Decision {
        let fitted = LiveSetlistWaveformMetrics.clampedWaveformHeight(
            measurement.assignedHeight - measurement.midiOverhead
        )
        let isInitial = measurement.previousMIDIOverhead == nil
        let overheadStable: Bool
        let paneChanged: Bool
        // A divider move only counts as a user resize once the pane has already
        // held the saved waveform. The first layouts often settle from the
        // minimum height up to the real one.
        let previousFitsSavedWaveform: Bool
        if let previousMIDIOverhead = measurement.previousMIDIOverhead {
            overheadStable = abs(measurement.midiOverhead - previousMIDIOverhead) < 0.5
            let previousAssigned = measurement.previousAssignedHeight ?? measurement.assignedHeight
            paneChanged = abs(measurement.assignedHeight - previousAssigned) > 0.5
            previousFitsSavedWaveform = previousAssigned + 0.5
                >= measurement.storedWaveformHeight + previousMIDIOverhead
        } else {
            overheadStable = false
            paneChanged = false
            previousFitsSavedWaveform = false
        }
        let userAdjusted = paneChanged && overheadStable && previousFitsSavedWaveform
        let paneFitsSavedWaveform = measurement.assignedHeight + 0.5
            >= measurement.storedWaveformHeight + measurement.midiOverhead
        let apply = userAdjusted || paneFitsSavedWaveform || measurement.forceFit
        guard apply else {
            return Decision(waveformHeight: nil, persistWaveformHeight: false)
        }
        let persist = userAdjusted || (isInitial && paneFitsSavedWaveform)
        return Decision(waveformHeight: fitted, persistWaveformHeight: persist)
    }

    /// Minimum content height that forces the split divider down when lanes
    /// appear. `nil` uses the normal drag floor.
    static func reservedPaneHeight(
        storedWaveformHeight: CGFloat,
        midiOverhead: CGFloat,
        isReserving: Bool
    ) -> CGFloat? {
        guard isReserving, midiOverhead > 0.5 else { return nil }
        return storedWaveformHeight + midiOverhead
    }
}
