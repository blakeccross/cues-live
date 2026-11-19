import SwiftUI

extension EditView {
    /// Meter, tempo and marker rulers at `contentWidth`, which a live zoom changes before the
    /// editor's zoom does.
    func timelineRulerStack(contentWidth: CGFloat, displayWidth: CGFloat) -> some View {
        timelineRulerSection(contentWidth: contentWidth, displayWidth: displayWidth)
            .background(AppColors.Timeline.stickyRulerBackground)
            .frame(width: displayWidth, height: TimelineLayout.topRulerHeight, alignment: .leading)
    }

    /// What the rulers show, for the AppKit ruler that covers them during a live zoom.
    var timelineLiveRuler: TimelineLiveRuler {
        TimelineLiveRuler(
            duration: timelineDuration,
            contentWidth: timelineContentWidth,
            sections: displaySections,
            selectedSectionID: selectedSectionMarkerID,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            loopSectionIDs: loopSectionIDs,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            playRange: timeline.playRange.resolved(songEnd: timeline.duration)
        )
    }

    func timelineTimeRuler(contentWidth: CGFloat, displayWidth: CGFloat) -> some View {
        TimelineTimeRulerView(
            duration: timelineDuration,
            contentWidth: contentWidth,
            displayWidth: displayWidth,
            height: TimelineLayout.rulerHeight
        )
        .overlay(alignment: .topLeading) {
            TimelinePlayRangeFlags(
                playRange: timeline.playRange,
                songEnd: timeline.duration,
                duration: timelineDuration,
                contentWidth: contentWidth,
                displayWidth: displayWidth,
                height: TimelineLayout.rulerHeight,
                tempoChanges: normalizedTempoChanges,
                timeSignatureChanges: normalizedTimeSignatureChanges,
                preview: playRangePreview,
                onMove: movePlayRange(to:),
                onReset: resetPlayRange
            )
        }
        .frame(width: displayWidth, height: TimelineLayout.rulerHeight, alignment: .leading)
    }

    private func timelineRulerSection(contentWidth: CGFloat, displayWidth: CGFloat) -> some View {
        TimelineRulerView(
            duration: timelineDuration,
            contentWidth: contentWidth,
            displayWidth: displayWidth,
            sections: displaySections,
            tempoChanges: normalizedTempoChanges,
            timeSignatureChanges: normalizedTimeSignatureChanges,
            cuedSectionID: cuedSectionID,
            cueFlashPhase: cueFlashPhase,
            selectedSectionID: $selectedSectionMarkerID,
            editingSectionID: $editingSectionID,
            loopSectionIDs: loopSectionIDs,
            sectionMarkerHeight: TimelineLayout.sectionMarkerHeight,
            timeSignatureRulerHeight: TimelineLayout.timeSignatureRulerHeight,
            tempoRulerHeight: TimelineLayout.tempoRulerHeight,
            isPlaying: audioEngine.isPlaying,
            onCueSection: cueSection,
            onToggleLoopSection: toggleLoopSection,
            onAddSection: addSection,
            onRenameSection: { section, name in applySectionRename(name, to: section) },
            onManageSectionNames: { activeSheet = .sectionNames },
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
        .id("\(displaySections.map(\.id))|\(normalizedTempoChanges.map(\.id))|\(normalizedTimeSignatureChanges.map(\.id))")
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
