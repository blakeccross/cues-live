import SwiftUI

extension EditView {
    var timelineRulerStack: some View {
        timelineRulerSection
            .background(AppColors.Timeline.stickyRulerBackground)
            .frame(width: timelineDisplayWidth, height: TimelineLayout.topRulerHeight, alignment: .leading)
    }

    var timelineTimeRuler: some View {
        TimelineTimeRulerView(
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            displayWidth: timelineDisplayWidth,
            height: TimelineLayout.rulerHeight
        )
        .overlay(alignment: .topLeading) {
            TimelinePlayRangeFlags(
                playRange: timeline.playRange,
                songEnd: timeline.duration,
                duration: timelineDuration,
                contentWidth: timelineContentWidth,
                displayWidth: timelineDisplayWidth,
                height: TimelineLayout.rulerHeight,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                preview: playRangePreview,
                onMove: movePlayRange(to:),
                onReset: resetPlayRange
            )
        }
        .frame(width: timelineDisplayWidth, height: TimelineLayout.rulerHeight, alignment: .leading)
    }

    private var timelineRulerSection: some View {
        TimelineRulerView(
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            displayWidth: timelineDisplayWidth,
            sections: displaySections,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            loopSectionIDs: loopSectionIDs,
            sectionMarkerHeight: TimelineLayout.sectionMarkerHeight,
            timeSignatureRulerHeight: TimelineLayout.timeSignatureRulerHeight,
            tempoRulerHeight: TimelineLayout.tempoRulerHeight,
            isPlaying: audioEngine.isPlaying,
            onCueSection: cueSection,
            onToggleLoopSection: toggleLoopSection,
            onAddSection: addSection,
            onRenameSection: beginRenameSection,
            onRemoveMarker: removeMarker,
            previewSections: previewSections(_:),
            onEditSectionEdge: applySectionEdge(_:),
            onTimeSignatureRulerTap: handleTimeSignatureRulerTap,
            onEditTimeSignatureMarker: { marker in
                activeSheet = .timeSignatureChange(TimeSignatureLanePrompt(
                    measure: marker.startMeasure,
                    numerator: marker.numerator,
                    denominator: marker.denominator,
                    markerID: marker.id
                ))
            },
            onDeleteTimeSignatureMarker: deleteTimeSignatureMarker,
            onMoveTimeSignatureMarker: moveTimeSignatureMarker,
            onTempoRulerTap: handleTempoRulerTap,
            onEditTempoMarker: { marker in
                activeSheet = .tempoChange(TempoLanePrompt(
                    measure: marker.startMeasure,
                    bpm: marker.bpm,
                    markerID: marker.id
                ))
            },
            onDeleteTempoMarker: deleteTempoMarker,
            onMoveTempoMarker: moveTempoMarker,
            onTempoOperations: { showingTempoOperations = true }
        )
        .frame(height: TimelineLayout.topRulerHeight)
        .id("\(displaySections.map(\.id))|\(timelineContentWidth)|\(normalizedTempoChanges.map(\.id))|\(normalizedTimeSignatureChanges.map(\.id))")
        .popover(isPresented: $showingTempoOperations, arrowEdge: .bottom) {
            TempoOperationsMenu(
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                playhead: audioEngine.currentTime,
                onApply: applyTempoOperation
            )
        }
    }

    private func rulerLaneLabel(_ title: String, height: CGFloat) -> some View {
        Text(title)
            .font(AppTypography.Compact.label)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.horizontal, AppSpacing.xs)
            .frame(height: height)
    }

    private var rulerLaneDivider: some View {
        Rectangle()
            .fill(AppColors.Timeline.divider)
            .frame(height: 1)
            .allowsHitTesting(false)
    }

    var trackHeaderRulerCorner: some View {
        VStack(spacing: 0) {
            rulerLaneLabel("Meter", height: TimelineLayout.timeSignatureRulerHeight)
            rulerLaneLabel("Tempo", height: TimelineLayout.tempoRulerHeight)
            rulerLaneLabel("Markers", height: TimelineLayout.sectionMarkerHeight)
        }
        .frame(width: TimelineLayout.trackHeaderWidth, height: TimelineLayout.topRulerHeight)
        .background(AppColors.Timeline.trackHeaderBackground)
        .overlay(alignment: .bottom) { rulerLaneDivider }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AppColors.Timeline.divider)
                .frame(width: 1)
        }
    }

    var trackHeaderTimeRulerCorner: some View {
        rulerLaneLabel("Time", height: TimelineLayout.rulerHeight)
            .frame(width: TimelineLayout.trackHeaderWidth)
            .background(AppColors.Timeline.trackHeaderBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(AppColors.Timeline.divider)
                    .frame(width: 1)
            }
    }
}
