import SwiftUI

struct MixerFaderColumn: View {
    @Binding var value: Double
    let groupID: UUID?
    let height: CGFloat
    /// Audible mix only — must not write SwiftData (avoids @Query rebuilds mid-drag).
    let onLiveVolumeChange: (Double) -> Void
    let onEditingEnded: () -> Void

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    private let trackWidth: CGFloat = 4
    private let thumbWidth: CGFloat = 40
    private let thumbHeight: CGFloat = MixerFaderScale.thumbHeight
    private let meterWidth: CGFloat = 5
    private let labelWidth: CGFloat = 22
    private let labelGap: CGFloat = 2
    private let tickWidth: CGFloat = 8
    private let tickGapFromTrack: CGFloat = 4
    private let readoutHeight: CGFloat = 16

    private var columnWidth: CGFloat {
        labelWidth + labelGap + thumbWidth
    }

    private var displayedValue: Double {
        isDragging ? dragValue : value
    }

    var body: some View {
        let faderHeight = max(height - readoutHeight - AppSpacing.xxs, 1)

        VStack(spacing: AppSpacing.xxs) {
            HStack(spacing: MixerFaderScale.meterGap) {
                MixerReadoutBox(text: TrackMixReadout.volumeText(forGain: displayedValue))
                GroupPeakHoldReadout(groupID: groupID)
            }
            .frame(width: columnWidth + MixerFaderScale.meterGap + meterWidth, height: readoutHeight)

            HStack(alignment: .top, spacing: MixerFaderScale.meterGap) {
                faderTrack
                GroupPeakMeterBar(groupID: groupID, width: meterWidth, height: faderHeight)
            }
            .frame(height: faderHeight)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: height)
    }

    private var faderTrack: some View {
        GeometryReader { geometry in
            let trackHeight = geometry.size.height
            let travel = max(trackHeight - thumbHeight, 1)
            let trackCenterX = thumbWidth / 2
            let thumbCenterY = markY(
                forNormalized: MixerFaderScale.normalizedPosition(forLinearGain: displayedValue),
                in: trackHeight
            )
            let thumbY = thumbCenterY - thumbHeight / 2

            ZStack(alignment: .topLeading) {
                // Labels sit on the meter side so the meter reads against the scale.
                scaleLabels(in: trackHeight)
                    .offset(x: thumbWidth + labelGap)
                scaleTicks(in: trackHeight, trackCenterX: trackCenterX)

                RoundedRectangle(cornerRadius: trackWidth / 2, style: .continuous)
                    .fill(AppColors.separator)
                    .frame(width: trackWidth, height: trackHeight)
                    .offset(x: trackCenterX - trackWidth / 2)

                faderThumb
                    .offset(y: thumbY)
            }
            .frame(width: columnWidth, height: trackHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            dragValue = value
                            isDragging = true
                        }
                        setLiveValue(fromCenterY: drag.location.y, trackHeight: trackHeight, travel: travel)
                    }
                    .onEnded { _ in
                        if isDragging {
                            value = dragValue
                        }
                        isDragging = false
                        onEditingEnded()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded(resetToUnity))
        }
        .frame(width: columnWidth)
        .transaction { transaction in
            if isDragging {
                transaction.disablesAnimations = true
            }
        }
    }

    private var faderThumb: some View {
        RoundedRectangle(cornerRadius: AppRadius.xxs, style: .continuous)
            .fill(AppColors.Mixer.faderThumb)
            .overlay {
                VStack(spacing: MixerFaderScale.gripLineSpacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(AppColors.Mixer.faderGrip)
                            .frame(height: 1)
                    }
                }
                .padding(.horizontal, AppSpacing.compact)
            }
            .overlay {
                Rectangle()
                    .fill(AppColors.Mixer.faderThumbLine)
                    .frame(height: 2)
                    .padding(.horizontal, AppSpacing.xxs)
            }
            .frame(width: thumbWidth, height: thumbHeight)
    }

    private func scaleLabels(in trackHeight: CGFloat) -> some View {
        let labelHeight: CGFloat = 10
        let marks = visibleMarkerLabels(in: trackHeight, labelHeight: labelHeight)

        return ZStack(alignment: .topLeading) {
            ForEach(marks, id: \.self) { db in
                let y = markY(
                    forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                    in: trackHeight
                )
                let isUnity = db == 0

                Text(MixerFaderScale.markerLabel(for: db))
                    .font(isUnity ? AppTypography.Compact.faderScaleEmphasized : AppTypography.Compact.faderScale)
                    .foregroundStyle(isUnity ? AppColors.textSecondary : AppColors.textTertiary)
                    .frame(width: labelWidth, height: labelHeight, alignment: .trailing)
                    .offset(y: y - labelHeight / 2)
            }
        }
        .frame(width: labelWidth, height: trackHeight, alignment: .topLeading)
    }

    /// Every 6 dB gets a tick, left of the track. Labels that would collide are dropped, except +6 and 0.
    private func visibleMarkerLabels(in trackHeight: CGFloat, labelHeight: CGFloat) -> [Int] {
        let minGap = labelHeight + 1
        var chosen: [(db: Int, y: CGFloat)] = []

        for db in MixerFaderScale.markerDecibels {
            let y = markY(
                forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                in: trackHeight
            )
            let pinned = db == Int(MixerFaderScale.maxBoostDB) || db == 0
            if let last = chosen.last, y - last.y < minGap {
                if pinned, last.db != Int(MixerFaderScale.maxBoostDB), last.db != 0 {
                    chosen.removeLast()
                    chosen.append((db, y))
                }
                continue
            }
            chosen.append((db, y))
        }

        return chosen.map(\.db)
    }

    private func scaleTicks(in trackHeight: CGFloat, trackCenterX: CGFloat) -> some View {
        let trackHalf = trackWidth / 2

        return ZStack(alignment: .topLeading) {
            ForEach(MixerFaderScale.markerDecibels, id: \.self) { db in
                let y = markY(
                    forNormalized: MixerFaderScale.normalizedPosition(forDecibels: Double(db)),
                    in: trackHeight
                )
                let isUnity = db == 0
                let width = isUnity ? tickWidth + 4 : tickWidth
                let tickColor = isUnity ? AppColors.textSecondary : AppColors.Mixer.scaleTick

                Rectangle()
                    .fill(tickColor)
                    .frame(width: width, height: 1)
                    .offset(
                        x: trackCenterX - trackHalf - tickGapFromTrack - width,
                        y: y - 0.5
                    )
            }
        }
        .frame(width: columnWidth, height: trackHeight, alignment: .topLeading)
    }

    private func markY(forNormalized normalized: Double, in trackHeight: CGFloat) -> CGFloat {
        thumbHeight / 2 + CGFloat(normalized) * max(trackHeight - thumbHeight, 1)
    }

    /// Each click also moves the thumb through the drag gesture, so clear the drag state too:
    /// a drag ending after this must not write the clicked position back over unity.
    private func resetToUnity() {
        isDragging = false
        dragValue = 1
        value = 1
        onLiveVolumeChange(1)
        onEditingEnded()
    }

    private func setLiveValue(fromCenterY y: CGFloat, trackHeight: CGFloat, travel: CGFloat) {
        let clampedCenter = min(max(y, thumbHeight / 2), trackHeight - thumbHeight / 2)
        let normalized = Double((clampedCenter - thumbHeight / 2) / travel)
        let newValue = MixerFaderScale.linearGain(forNormalizedPosition: normalized)
        dragValue = newValue
        onLiveVolumeChange(newValue)
    }
}

/// Reads peak meters in isolation so 30 Hz updates don't rebuild parent fader geometry.
private struct GroupPeakMeterBar: View {
    let groupID: UUID?
    let width: CGFloat
    let height: CGFloat

    @Bindable private var audioEngine = AudioEngineManager.shared

    var body: some View {
        let meterLevel = audioEngine.groupMeterLevel(for: groupID)

        GeometryReader { geometry in
            let inset = MixerFaderScale.thumbHeight / 2
            let travel = max(geometry.size.height - MixerFaderScale.thumbHeight, 1)
            let fill = travel * MixerFaderScale.faderMeterFillFraction(forPeak: meterLevel)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: MixerFaderScale.meterCornerRadius, style: .continuous)
                    .fill(AppColors.separator)

                RoundedRectangle(cornerRadius: MixerFaderScale.meterCornerRadius, style: .continuous)
                    .fill(AppColors.Mixer.faderLevel)
                    .frame(height: fill)
            }
            .padding(.vertical, inset)
        }
        .frame(width: width, height: height)
    }
}

/// One of the two numbers above a fader.
private struct MixerReadoutBox: View {
    let text: String
    var textColor: Color = AppColors.textPrimary

    var body: some View {
        Text(text)
            .font(AppTypography.Compact.mixReadout.monospacedDigit())
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
    }
}

/// Loudest level since the last reset; click to reset. Reads meters in isolation like
/// `GroupPeakMeterBar`, so 30 Hz updates don't rebuild the fader.
private struct GroupPeakHoldReadout: View {
    let groupID: UUID?

    @Bindable private var audioEngine = AudioEngineManager.shared
    @State private var heldPeak: Float = 0

    var body: some View {
        let meterLevel = audioEngine.groupMeterLevel(for: groupID)

        MixerReadoutBox(
            text: TrackMixReadout.peakText(forPeak: heldPeak),
            textColor: heldPeak >= 1 ? AppColors.error : AppColors.textPrimary
        )
        .contentShape(Rectangle())
        .onTapGesture { heldPeak = 0 }
        .onChange(of: meterLevel) { _, level in
            if level > heldPeak { heldPeak = level }
        }
        .help("Peak level. Click to reset.")
    }
}
